import Foundation

/// A framework-independent description of an audio stream - just enough to
/// decide whether an iPod Classic will play it. The layer above the core fills it
/// in (AVFoundation), so the rules themselves can be tested without files.
public struct AudioStream: Sendable, Hashable {
    /// Four-character format identifier from CoreAudio: `.mp3`, `aac `, `alac`, `lpcm`.
    public let formatID: String
    /// Bits per sample. Irrelevant for lossy formats - then 0.
    public let bitsPerChannel: Int
    public let sampleRate: Int
    public let channels: Int
    /// Average bitrate in bits per second; 0 when unknown.
    public let bitRate: Int
    /// File extension, lowercase, without the dot.
    public let fileExtension: String

    public init(formatID: String, bitsPerChannel: Int, sampleRate: Int, channels: Int, bitRate: Int, fileExtension: String) {
        self.formatID = formatID
        self.bitsPerChannel = bitsPerChannel
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitRate = bitRate
        self.fileExtension = fileExtension
    }
}

/// Whether an iPod Classic 7G will play a given file - and what to replace it with if not.
///
/// Limits taken from Apple's specification for the iPod Classic and confirmed on
/// a real device: a whole album in 24-bit ALAC had zero plays since March
/// 2025, against 879 plays in the rest of the library.
public enum AudioCompatibility {

    public enum Verdict: Sendable, Hashable {
        /// The file works as it is.
        case supported
        /// It can be transcoded; `target` says to what.
        case convertible(reason: String, target: Target)
        /// It will not play, and we cannot transcode it.
        case rejected(reason: String)

        public var isSupported: Bool { if case .supported = self { return true }; return false }
        public var reason: String? {
            switch self {
            case .supported: return nil
            case .convertible(let reason, _), .rejected(let reason): return reason
            }
        }
    }

    /// Conversion target format. Rule: **the highest supported** - a lossless
    /// source stays lossless (16-bit ALAC), a lossy one is never encoded
    /// a second time, only rejected or rewrapped.
    public enum Target: Sendable, Hashable {
        /// 16-bit ALAC, source sample rate capped at 48 kHz.
        case appleLossless(sampleRate: Int)
        /// AAC-LC at the given bitrate - for sources that cannot be stored
        /// losslessly within the device's limits.
        case aac(bitRate: Int)

        public var label: String {
            switch self {
            case .appleLossless(let rate): return "Apple Lossless 16-bit \(String(format: "%.1f", Double(rate) / 1000)) kHz"
            case .aac(let rate): return "AAC \(rate / 1000) kbps"
            }
        }

        /// The kind that must be written to the `mhit` record after conversion.
        public var kindForDevice: TrackFileKind {
            switch self {
            case .appleLossless: return .appleLossless
            case .aac: return .aac
            }
        }
    }

    /// Limits of the default profile (Classic). Kept as a shortcut for code
    /// that does not know the model; the rule takes them from `IPodCapabilities`.
    public static let maximumSampleRate = IPodCapabilities.classic.maximumSampleRate
    public static let maximumBitDepth = IPodCapabilities.classic.maximumBitDepth
    public static let maximumChannels = IPodCapabilities.classic.maximumChannels
    /// Container/codec formats that no iPod knows.
    public static let unknownToDevice: Set<String> = ["flac", "ogg", "oga", "opus", "wma", "ape", "wv", "mpc", "dsf", "dff"]

    /// What the verdict is for: a file about to go onto the iPod, or one already on it.
    public enum Purpose: Sendable {
        /// A file to add - we must be able to describe it in the database.
        case adding
        /// A file already on the iPod - all that matters is whether the iPod plays it.
        case playing
    }

    /// Verdict for a stream on a given device. Without a model, the
    /// Classic profile applies - the one the rules were measured on.
    public static func verdict(for stream: AudioStream, on device: IPodCapabilities = .classic,
                               purpose: Purpose = .adding) -> Verdict {
        let extensionLower = stream.fileExtension.lowercased()
        if unknownToDevice.contains(extensionLower) {
            // FLAC and friends are lossless, so the target comes from the profile: ALAC
            // where the device knows it, AAC where it does not.
            return .convertible(reason: "\(extensionLower.uppercased()) is not a format the iPod can read",
                                target: device.losslessTarget(sampleRate: stream.sampleRate))
        }
        if stream.channels > device.maximumChannels {
            return .rejected(reason: "\(stream.channels) channels; the iPod plays mono and stereo only")
        }

        switch stream.formatID {
        case ".mp3":
            guard stream.sampleRate >= 8_000, stream.sampleRate <= device.maximumSampleRate else {
                return .convertible(reason: "MP3 at \(khz(stream.sampleRate)) is outside the iPod's range",
                                    target: .aac(bitRate: device.aacBitRate))
            }
            guard stream.bitRate <= device.maximumMP3BitRate else {
                return .convertible(reason: "MP3 above \(device.maximumMP3BitRate / 1000) kbps",
                                    target: .aac(bitRate: device.aacBitRate))
            }
            return .supported

        case "aac ", "aacp", "paac":
            guard stream.sampleRate <= device.maximumSampleRate else {
                return .convertible(reason: "AAC at \(khz(stream.sampleRate))", target: .aac(bitRate: device.aacBitRate))
            }
            return .supported

        case "aach", "aacl", "aacf":
            return .convertible(reason: "HE-AAC is not supported by the iPod", target: .aac(bitRate: device.aacBitRate))

        case "alac":
            guard device.supportsAppleLossless else {
                return .convertible(reason: "\(device.name) does not play Apple Lossless",
                                    target: .aac(bitRate: device.aacBitRate))
            }
            if stream.bitsPerChannel > device.maximumBitDepth || stream.sampleRate > device.maximumSampleRate {
                let detail = stream.bitsPerChannel > device.maximumBitDepth
                    ? "\(stream.bitsPerChannel)-bit Apple Lossless"
                    : "Apple Lossless at \(khz(stream.sampleRate))"
                return .convertible(reason: "\(detail); the iPod plays \(device.maximumBitDepth)-bit up to \(khz(device.maximumSampleRate))",
                                    target: device.losslessTarget(sampleRate: stream.sampleRate))
            }
            return .supported

        case "lpcm":
            // The iPod plays AIFF (the Classic plays 16-bit AIFF from CD import, although
            // their record describes Apple Lossless), but we cannot describe a new AIFF
            // record: we have none written by Apple. When adding, it therefore
            // goes in as ALAC - it keeps every bit, and its description is
            // measured (checked on Ozzmosis: after decoding the samples are identical
            // byte for byte, and the file is 24% smaller).
            let isAIFF = extensionLower == "aif" || extensionLower == "aiff"
            if isAIFF, purpose == .adding {
                return .convertible(reason: "AIFF is stored as Apple Lossless: every sample kept, in a smaller file",
                                    target: device.losslessTarget(sampleRate: stream.sampleRate))
            }
            guard isAIFF || extensionLower == "wav" else {
                return .convertible(reason: "uncompressed audio in a container the iPod does not read",
                                    target: device.losslessTarget(sampleRate: stream.sampleRate))
            }
            if stream.bitsPerChannel > device.maximumBitDepth || stream.sampleRate > device.maximumSampleRate {
                let detail = stream.bitsPerChannel > device.maximumBitDepth
                    ? "\(stream.bitsPerChannel)-bit \(extensionLower.uppercased())"
                    : "\(extensionLower.uppercased()) at \(khz(stream.sampleRate))"
                return .convertible(reason: "\(detail); the iPod plays \(device.maximumBitDepth)-bit up to \(khz(device.maximumSampleRate))",
                                    target: device.losslessTarget(sampleRate: stream.sampleRate))
            }
            return .supported

        default:
            if stream.formatID.hasPrefix("aac") { return .supported }
            return .rejected(reason: "unknown audio format \u{201C}\(stream.formatID.trimmingCharacters(in: .whitespaces))\u{201D}")
        }
    }

    /// Short description of the stream for the interface, e.g. "ALAC 24-bit 48 kHz".
    public static func label(for stream: AudioStream) -> String {
        var parts: [String] = [name(of: stream.formatID)]
        if stream.bitsPerChannel > 0 { parts.append("\(stream.bitsPerChannel)-bit") }
        parts.append(khz(stream.sampleRate))
        if stream.bitRate > 0, stream.bitsPerChannel == 0 { parts.append("\(stream.bitRate / 1000) kbps") }
        return parts.joined(separator: " ")
    }

    static func name(of formatID: String) -> String {
        switch formatID {
        case ".mp3": return "MP3"
        case "alac": return "ALAC"
        case "lpcm": return "PCM"
        default: return formatID.hasPrefix("aac") ? "AAC" : formatID.trimmingCharacters(in: .whitespaces).uppercased()
        }
    }

    static func khz(_ rate: Int) -> String {
        rate % 1000 == 0 ? "\(rate / 1000) kHz" : String(format: "%.1f kHz", Double(rate) / 1000)
    }
}
