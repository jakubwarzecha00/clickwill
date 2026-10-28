import Foundation
import ITDBKit

/// The same song on the iPod several times: two imports of the same album,
/// once from MP3, once from FLAC, or a sync that added a copy instead of
/// replacing the file. The same rule as when adding (`SongIndex`): title,
/// artist and album after simplification, length within two seconds.
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public struct Copy: Identifiable, Hashable, Sendable {
        public let id: UInt32
        /// Format description for the interface, e.g. "MP3 320 kbps".
        public let format: String
        public let playCount: UInt32
        public let fileMissing: Bool
    }

    public var id: UInt32 { keep.id }
    public let title: String
    public let artist: String
    public let album: String
    /// The copy that stays - the first according to `DuplicateGroup.rank`.
    public let keep: Copy
    public let remove: [Copy]
}

extension LibraryModel {

    /// Duplicate groups in the library, in the order of tracks on the iPod.
    public func duplicateGroups() -> [DuplicateGroup] {
        guard let library else { return [] }
        let unsupported = Set(formatVerdicts.filter { !$0.value.isSupported }.keys)
        return Self.duplicateClusters(library.tracks, missing: missingFileIDs, unsupported: unsupported).map { cluster in
            let copies = cluster.map { track in
                DuplicateGroup.Copy(id: track.uniqueID, format: formatLabels[track.uniqueID] ?? Self.formatGuess(track),
                                    playCount: track.playCount, fileMissing: missingFileIDs.contains(track.uniqueID))
            }
            let first = cluster[0]
            return DuplicateGroup(title: first.title ?? "", artist: first.artist ?? first.albumArtist ?? "",
                                  album: first.album ?? "", keep: copies[0], remove: Array(copies.dropFirst()))
        }
    }

    /// Copies of the same song, the best one at the start of each group.
    ///
    /// Which one stays: first the one that has a file, then the one the iPod plays,
    /// then the higher bitrate (ALAC before MP3, MP3 320 before 128), and finally
    /// more plays. On a tie, the earlier one in the library.
    public nonisolated static func duplicateClusters(_ tracks: [ITTrack], missing: Set<UInt32>,
                                              unsupported: Set<UInt32>) -> [[ITTrack]] {
        var byKey: [SongIndex.Key: [Int]] = [:]
        var keys: [SongIndex.Key] = []
        for (index, track) in tracks.enumerated() {
            guard let key = SongIndex.key(title: track.title, artist: track.artist ?? track.albumArtist, album: track.album) else { continue }
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(index)
        }

        func rank(_ index: Int) -> (Int, Int, UInt32, UInt32, Int) {
            let track = tracks[index]
            return (missing.contains(track.uniqueID) ? 0 : 1, unsupported.contains(track.uniqueID) ? 0 : 1,
                    track.bitRate, track.playCount, -index)
        }

        var clusters: [[ITTrack]] = []
        for key in keys {
            guard let indices = byKey[key], indices.count > 1 else { continue }
            // Length: each copy is compared with the first in the group, so the chain
            // 3:00, 3:02, 3:04 does not merge tracks that differ by 4 seconds.
            var groups: [[Int]] = []
            for index in indices.sorted(by: { tracks[$0].durationMilliseconds < tracks[$1].durationMilliseconds }) {
                if let last = groups.indices.last,
                   SongIndex.sameLength(tracks[groups[last][0]].durationMilliseconds, tracks[index].durationMilliseconds) {
                    groups[last].append(index)
                } else {
                    groups.append([index])
                }
            }
            for group in groups where group.count > 1 {
                clusters.append(group.sorted { rank($0) > rank($1) }.map { tracks[$0] })
            }
        }
        // In library order: a group stands where its first copy is.
        let position = Dictionary(tracks.enumerated().map { ($1.uniqueID, $0) }, uniquingKeysWith: { first, _ in first })
        func first(_ cluster: [ITTrack]) -> Int { cluster.compactMap { position[$0.uniqueID] }.min() ?? 0 }
        return clusters.sorted { first($0) < first($1) }
    }

    /// The format before the file scan: the extension and bitrate from the database.
    /// M4A is AAC or Apple Lossless - the bitrate tells them apart: AAC ends
    /// at 320 kbps, and 16-bit ALAC usually has 600-1000.
    public nonisolated static func formatGuess(_ track: ITTrack) -> String {
        let ext = (track.relativePath.map { ($0 as NSString).pathExtension } ?? "").lowercased()
        let kind: String
        switch ext {
        case "m4a", "m4p", "mp4": kind = track.bitRate > 500 ? "Apple Lossless" : "AAC"
        case "": kind = "Audio"
        default: kind = ext.uppercased()
        }
        return track.bitRate > 0 ? "\(kind) \(track.bitRate) kbps" : kind
    }
}
