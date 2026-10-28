import Foundation
import ITDBKit

/// A file chosen for an entry that has no file. It waits for `apply()` together
/// with the rest of the changes - until then nothing happens on the device.
///
/// This is not the same as adding a track (`PendingAddition`). There a new
/// `mhit` record is created; here the record already exists - it has its identifier, positions
/// in the tables, plays and artwork - and lacks only the file. That is why
/// it goes through `replacingFile`, which changes the path and parameters and does not touch
/// the rest of the record.
public struct PendingFileImport: Identifiable, Sendable {
    /// The `uniqueID` of the track whose file we restore.
    public let id: UInt32
    public let album: String
    public let title: String
    public let source: URL
    public let verdict: AudioCompatibility.Verdict
    public let formatLabel: String
    public let durationMilliseconds: UInt32
    public let bitRate: UInt32
    public let sampleRate: UInt32
    public let kind: TrackFileKind
    /// The file the track has on the iPod today - `nil` when restoring, where
    /// there simply is no file. When replacing, it goes away **only after** a successful
    /// database write, the same way as the original after a conversion: at no moment
    /// is there a state in which the entry points to an empty place.
    public var replacing: URL? = nil

    public var isReplacement: Bool { replacing != nil }

    public var target: AudioCompatibility.Target? {
        if case .convertible(_, let target) = verdict { return target }
        return nil
    }
    public var needsConversion: Bool { !verdict.isSupported }
}

/// A file that has been examined but not assigned yet. The interface shows its format
/// verdict and length from this, so it is clear whether it matched the same track before
/// anything goes into the queue.
public struct ImportCandidate: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let url: URL
    public let verdict: AudioCompatibility.Verdict
    public let formatLabel: String
    public let durationMilliseconds: UInt32
    /// The title from the file's tags; empty when the file has no tags.
    public let taggedTitle: String
    public let trackNumber: UInt32
    public let sizeBytes: UInt32
    public let bitRate: UInt32
    public let sampleRate: UInt32
    public let kind: TrackFileKind

    public var fileName: String { url.lastPathComponent }
    public var duration: TimeInterval { Double(durationMilliseconds) / 1000 }
    public var needsConversion: Bool { !verdict.isSupported }
    /// It will not play, and we cannot transcode it.
    public var isHopeless: Bool {
        if case .rejected = verdict { return true }
        return false
    }
    public var target: AudioCompatibility.Target? {
        if case .convertible(_, let target) = verdict { return target }
        return nil
    }
}

public enum FileImportError: Error, CustomStringConvertible {
    case unreadable(URL)
    case rejected(URL, reason: String)
    case notMissing(String)
    case sameFile(String)
    case currentFileUnknown(String)

    public var description: String {
        switch self {
        case .unreadable(let url): "unreadable audio file \(url.lastPathComponent)"
        case .rejected(let url, let reason): "\(url.lastPathComponent) rejected: \(reason)"
        case .notMissing(let title): "\(title) already has a file"
        case .sameFile(let title): "\(title) already uses this file"
        case .currentFileUnknown(let title): "current file of \(title) unknown (snapshot)"
        }
    }
}

extension LibraryModel {

    /// Reads the file and returns what is known about it. `nil` when it is not audio.
    /// Tags are read the same way as when importing whole albums - one source of truth
    /// on how the title and track number are taken from a file.
    public func inspect(_ url: URL) async -> ImportCandidate? {
        guard let read = try? await AudioImport.candidate(at: url, on: capabilities) else { return nil }
        let draft = read.draft
        return ImportCandidate(
            url: url,
            verdict: read.verdict,
            formatLabel: read.formatLabel,
            durationMilliseconds: draft.durationMilliseconds,
            taggedTitle: draft.title,
            trackNumber: draft.trackNumber,
            sizeBytes: draft.sizeBytes,
            bitRate: draft.bitRate,
            sampleRate: draft.sampleRate,
            kind: draft.kind)
    }

    /// Matches files from a folder to entries without a file.
    ///
    /// First by title - normalized so that "Zoom (Ft. Gunna)" matches
    /// "Zoom feat Gunna" - and what the title did not catch, we try by track
    /// number. One file goes to at most one entry; unmatched ones
    /// stay unmatched, because a mistake in that direction is silent and hard to
    /// notice on the device.
    public func matchFiles(in directory: URL, to rows: [TrackRow]) async -> [UInt32: ImportCandidate] {
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [:] }
        var candidates: [ImportCandidate] = []
        for url in contents.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
        where AudioImport.audioExtensions.contains(url.pathExtension.lowercased()) {
            if let candidate = await inspect(url) { candidates.append(candidate) }
        }

        var matches: [UInt32: ImportCandidate] = [:]
        var used: Set<URL> = []
        for row in rows {
            let key = Self.matchKey(row.displayTitle)
            guard !key.isEmpty,
                  let hit = candidates.first(where: { !used.contains($0.url) && Self.matchKey($0.taggedTitle) == key })
            else { continue }
            matches[row.id] = hit
            used.insert(hit.url)
        }
        for row in rows where matches[row.id] == nil && row.number > 0 {
            guard let hit = candidates.first(where: { !used.contains($0.url) && $0.trackNumber == row.number }) else { continue }
            matches[row.id] = hit
            used.insert(hit.url)
        }
        return matches
    }

    /// The title comparison key: without diacritics, ignoring case,
    /// without punctuation, without words marking a featured artist.
    ///
    /// We remove whole words, not character runs - "ft" cut from anywhere
    /// turns "Aftermath" into "aermath", and two different titles reduced to the
    /// same key mean a file put under the wrong track.
    nonisolated static func matchKey(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let guests: Set<String> = ["feat", "featuring", "ft", "featg"]
        return String(kept).split(separator: " ").map(String.init)
            .filter { !guests.contains($0) }
            .joined(separator: " ")
    }
}
