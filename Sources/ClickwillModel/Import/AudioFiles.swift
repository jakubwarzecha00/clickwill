import Foundation
import AVFoundation
import ITDBKit

/// Reading an audio file's parameters and converting it to a format the iPod plays.
/// The core knows only the rules (`AudioCompatibility`); here is everything that
/// needs AVFoundation.
public enum AudioFiles {

    /// Stream parameters from a file. `nil` when the file cannot be opened
    /// or has no audio track.
    public static func stream(at url: URL) async -> AudioStream? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let description = try? await track.load(.formatDescriptions).first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        else { return nil }
        let bitRate = (try? await track.load(.estimatedDataRate)).map { Int($0) } ?? 0
        return AudioStream(
            formatID: fourCharacterCode(basic.mFormatID),
            bitsPerChannel: Int(basic.mBitsPerChannel) > 0 ? Int(basic.mBitsPerChannel) : losslessBitDepth(basic),
            sampleRate: Int(basic.mSampleRate),
            channels: Int(basic.mChannelsPerFrame),
            bitRate: bitRate,
            fileExtension: url.pathExtension)
    }

    /// The verdict for a file on disk.
    public static func verdict(at url: URL) async -> AudioCompatibility.Verdict? {
        guard let stream = await stream(at: url) else { return nil }
        return AudioCompatibility.verdict(for: stream)
    }

    /// Transcodes a file to the format given by the verdict. Returns the URL of the
    /// resulting file in a temporary folder - the caller decides what to do with it.
    ///
    /// 16-bit ALAC is assembled with `AVAssetWriter`, because `AVAssetExportSession` has no
    /// ready preset for lossless with control over the bit depth.
    public static func convert(_ url: URL, to target: AudioCompatibility.Target, tags: FileTags? = nil,
                               progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioConversionError.noAudioTrack(url)
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-\(UUID().uuidString.prefix(8)).m4a")

        let settings: [String: Any]
        switch target {
        case .appleLossless(let rate):
            settings = [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitDepthHintKey: 16,
            ]
        case .aac(let bitRate):
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: bitRate,
            ]
        }

        let writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw AudioConversionError.cannotEncode(target) }
        writer.add(input)
        if let tags { writer.metadata = tags.metadataItems() }

        let reader = try AVAssetReader(asset: asset)
        // We decode to 16-bit PCM - that is the actual depth reduction,
        // the rest is just writing.
        let readerOutput = AVAssetReaderTrackOutput(track: source, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(readerOutput) else { throw AudioConversionError.cannotDecode(url.lastPathComponent) }
        reader.add(readerOutput)

        guard writer.startWriting() else { throw writer.error ?? AudioConversionError.cannotEncode(target) }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else { throw reader.error ?? AudioConversionError.cannotDecode(url.lastPathComponent) }

        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let queue = DispatchQueue(label: "clickwill.convert")
        // AVAssetWriter and friends are not Sendable, and their whole life cycle is
        // here and runs on one queue - that is exactly what the box is for.
        let pipeline = ConversionPipeline(reader: reader, readerOutput: readerOutput, writer: writer, input: input)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pipeline.run(on: queue, duration: duration, progress: progress) { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        return output
    }

    // MARK: - Helpers

    static func fourCharacterCode(_ value: AudioFormatID) -> String {
        let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        return String(bytes: bytes, encoding: .ascii) ?? "\(value)"
    }

    /// ALAC does not fill `mBitsPerChannel`; the depth sits in `mFormatFlags`
    /// (1 = 16 bits, 2 = 20, 3 = 24, 4 = 32).
    static func losslessBitDepth(_ basic: AudioStreamBasicDescription) -> Int {
        guard basic.mFormatID == kAudioFormatAppleLossless else { return 0 }
        switch basic.mFormatFlags {
        case 1: return 16
        case 2: return 20
        case 3: return 24
        case 4: return 32
        default: return 0
        }
    }
}

/// A box for AVFoundation objects used only from one queue.
private final class ConversionPipeline: @unchecked Sendable {
    private let reader: AVAssetReader
    private let readerOutput: AVAssetReaderTrackOutput
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput

    init(reader: AVAssetReader, readerOutput: AVAssetReaderTrackOutput, writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.reader = reader
        self.readerOutput = readerOutput
        self.writer = writer
        self.input = input
    }

    func run(on queue: DispatchQueue, duration: Double, progress: (@Sendable (Double) -> Void)?,
             completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                guard reader.status == .reading, let buffer = readerOutput.copyNextSampleBuffer() else {
                    input.markAsFinished()
                    if reader.status == .failed {
                        completion(.failure(reader.error ?? AudioConversionError.cannotDecode(reader.asset.description)))
                    } else {
                        writer.finishWriting { [self] in
                            if writer.status == .completed { completion(.success(())) }
                            else { completion(.failure(writer.error ?? AudioConversionError.writerFailed)) }
                        }
                    }
                    return
                }
                if let progress, duration > 0 {
                    let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
                    progress(min(1, max(0, seconds / duration)))
                }
                input.append(buffer)
            }
        }
    }
}

public enum AudioConversionError: Error, CustomStringConvertible {
    case noAudioTrack(URL)
    case cannotDecode(String)
    case cannotEncode(AudioCompatibility.Target)
    case writerFailed

    public var description: String {
        switch self {
        case .noAudioTrack(let url): "no audio track in \(url.lastPathComponent)"
        case .cannotDecode(let what): "cannot decode \(what)"
        case .cannotEncode(let target): "cannot encode to \(target.label)"
        case .writerFailed: "asset writer failed"
        }
    }
}
