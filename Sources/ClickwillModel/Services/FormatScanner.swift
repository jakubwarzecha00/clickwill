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
/// format limits. A library can have tens of thousands of files, so the results come in batches:
/// the view refreshes along the way, and the caller can stop the scan between
/// batches (e.g. when another library was loaded).
struct FormatScanner: Sendable {
    let paths: IPodPaths
    let capabilities: IPodCapabilities
    var files: any FileSystem = LocalFileSystem()
    /// How often results are handed over. Each batch redraws every screen that shows formats,
    /// so it depends on time and not on a number of files: a fast disk must not refresh more often.
    var deliveryInterval: Duration = .seconds(1)

    /// Takes tracks from `next` (usually `FormatScanQueue`) until it returns `nil`, and hands over
    /// the results every `deliveryInterval`; the last batch comes at the end and may be empty.
    /// `isCurrent` is asked before taking each track: `false` ends the scan
    /// without handing over the rest, and the track not taken stays in the queue for a newer scan.
    /// Result: whether the scan went through all tracks.
    func scan(next: () -> ITTrack?, isolation: isolated (any Actor)? = #isolation,
              isCurrent: () -> Bool, deliver: (FormatReport) -> Void) async -> Bool {
        var batch = FormatReport()
        var lastDelivery = ContinuousClock.now
        while true {
            guard isCurrent() else { return false }
            guard let track = next() else { break }
            // A missing file is not a format verdict - the missing files count shows it.
            guard let found = await inspect(track) else { continue }
            batch.verdicts[track.uniqueID] = found.verdict
            batch.labels[track.uniqueID] = found.label
            if ContinuousClock.now - lastDelivery >= deliveryInterval {
                guard isCurrent() else { return false }
                deliver(batch)
                batch = FormatReport()
                lastDelivery = .now
            }
        }
        guard isCurrent() else { return false }
        deliver(batch)
        return true
    }

    /// The disk is touched here and only here. `nonisolated`, so it never runs on the caller's
    /// actor: the caller is the main thread, and an iPod's disk can stall for seconds.
    private nonisolated func inspect(_ track: ITTrack) async -> (verdict: AudioCompatibility.Verdict, label: String)? {
        guard let url = track.fileURL(on: paths), files.fileExists(at: url),
              let stream = await AudioFiles.stream(at: url) else { return nil }
        return (AudioCompatibility.verdict(for: stream, on: capabilities, purpose: .playing), AudioCompatibility.label(for: stream))
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
