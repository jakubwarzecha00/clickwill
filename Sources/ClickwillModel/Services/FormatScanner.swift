import Foundation
import ITDBKit

/// Format compatibility verdicts for files on the iPod: whether the iPod plays a file and how to
/// describe it in the interface ("ALAC 24-bit 48 kHz").
public struct FormatReport: Sendable {
    public internal(set) var verdicts: [UInt32: AudioCompatibility.Verdict] = [:]
    public internal(set) var labels: [UInt32: String] = [:]
    /// Whether the scan went through the whole library.
    public internal(set) var isComplete = false

    mutating func merge(_ other: FormatReport) {
        verdicts.merge(other.verdicts) { _, new in new }
        labels.merge(other.labels) { _, new in new }
    }
}

/// Reads the header of every audio file on the iPod and judges it against the model's
/// format limits. The library has over a thousand files, so the results come in batches:
/// the view refreshes along the way, and the caller can stop the scan between
/// batches (e.g. when another library was loaded).
struct FormatScanner {
    let paths: IPodPaths
    let capabilities: IPodCapabilities
    var files: any FileSystem = LocalFileSystem()
    var batchSize = 50

    /// Takes tracks from `next` (usually `FormatScanQueue`) until it returns `nil`,
    /// and hands over the results in batches of `batchSize` files; the last may be smaller.
    /// `isCurrent` is asked before taking each track: `false` ends the scan
    /// without handing over the rest, and the track not taken stays in the queue for a newer scan.
    /// Result: whether the scan went through all tracks.
    func scan(next: () -> ITTrack?, isolation: isolated (any Actor)? = #isolation,
              isCurrent: () -> Bool, deliver: (FormatReport) -> Void) async -> Bool {
        var batch = FormatReport()
        while true {
            guard isCurrent() else { return false }
            guard let track = next() else { break }
            // A missing file is not a format verdict - the missing files count shows it.
            guard let url = track.fileURL(on: paths), files.fileExists(at: url),
                  let stream = await AudioFiles.stream(at: url) else { continue }
            batch.verdicts[track.uniqueID] = AudioCompatibility.verdict(for: stream, on: capabilities, purpose: .playing)
            batch.labels[track.uniqueID] = AudioCompatibility.label(for: stream)
            if batch.verdicts.count == batchSize {
                guard isCurrent() else { return false }
                deliver(batch)
                batch = FormatReport()
            }
        }
        guard isCurrent() else { return false }
        deliver(batch)
        return true
    }
}

/// A conversion request - waits for the write, like the other changes.
struct ConversionJob: Sendable {
    let trackID: UInt32
    let album: String
    let title: String
    let source: URL
    let target: AudioCompatibility.Target
    let fromLabel: String
    /// The folder for the original. `nil` means a deliberate consent to no copy.
    let archiveDirectory: URL?
}

public enum ConversionQueueError: Error, CustomStringConvertible {
    case fileMissing(String)
    case notScanned(String)
    case notConvertible(String, reason: String)

    public var description: String {
        switch self {
        case .fileMissing(let title): "\(title): no file"
        case .notScanned(let title): "\(title): format not scanned yet"
        case .notConvertible(let title, let reason): "\(title): not convertible: \(reason)"
        }
    }
}
