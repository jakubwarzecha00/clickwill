import Foundation

/// Exactly what will disappear from the database when tracks are removed.
public struct TrackRemoval: Sendable {
    public struct Item: Sendable {
        public let uniqueID: UInt32
        public let title: String
        public let album: String
        public let path: String
        /// Whether the file exists on the device. `false` for dead entries.
        public let hasFile: Bool
    }

    public let items: [Item]
    /// How many entries will disappear from playlists, counting all copies.
    public let playlistEntries: Int
    /// How many browse tables need remapping.
    public let browseTables: Int
    /// Files to delete from disk - only those that really exist.
    public let filesToDelete: [String]

    public var isEmpty: Bool { items.isEmpty }
}

public enum TrackRemovalError: Error, CustomStringConvertible {
    case nothingToRemove
    case unknownTrack(UInt32)
    case indexOutOfRange(criterion: UInt32, entry: UInt32)
    case countMismatch(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .nothingToRemove:
            return "No song was chosen to delete."
        case .unknownTrack(let id):
            return "Song \(id) is no longer on the iPod."
        case .indexOutOfRange(let criterion, let entry):
            return "Clickwill stopped deleting because one of the iPod's menus points at a song that isn't there (\(criterion), \(entry)). Nothing was changed. Choose Send Feedback so I can look into it."
        case .countMismatch(let expected, let got):
            return "Clickwill stopped deleting because one of the iPod's menus didn't check out (\(got) of \(expected)). Nothing was changed. Choose Send Feedback so I can look into it."
        }
    }
}

extension ITLibrary {

    /// Determines the scope of the removal. Changes nothing.
    public func planRemoval(uniqueIDs: Set<UInt32>, fileExists: (String) -> Bool) throws -> TrackRemoval {
        guard !uniqueIDs.isEmpty else { throw TrackRemovalError.nothingToRemove }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.uniqueID, $0) })
        var items: [TrackRemoval.Item] = []
        var files: [String] = []

        for id in uniqueIDs.sorted() {
            guard let track = byID[id] else { throw TrackRemovalError.unknownTrack(id) }
            let path = track.relativePath ?? ""
            let present = path.isEmpty ? false : fileExists(path)
            items.append(TrackRemoval.Item(
                uniqueID: id, title: track.title ?? "", album: track.album ?? "",
                path: path, hasFile: present))
            if present { files.append(path) }
        }

        var entries = 0
        var tables = 0
        for section in sections {
            guard case .playlists(let playlists) = section.content else { continue }
            for playlist in playlists {
                entries += playlist.entries.filter { uniqueIDs.contains($0.trackID) }.count
                if playlist.isMaster {
                    tables += playlist.mhods.filter { $0.type == .libraryPlaylistIndex }.count
                }
            }
        }
        return TrackRemoval(items: items, playlistEntries: entries,
                            browseTables: tables, filesToDelete: files)
    }

    /// Removes tracks from the database.
    ///
    /// Browse tables hold record **positions**, not identifiers, so
    /// it is not enough to throw out the removed entries - every position greater than
    /// a removed one must move down. Alphabetical jump bars are recalculated from
    /// how many positions were lost in each letter's range.
    public func removingTracks(uniqueIDs: Set<UInt32>) throws -> ITLibrary {
        guard !uniqueIDs.isEmpty else { throw TrackRemovalError.nothingToRemove }
        let original = tracks

        // Old position -> new position, or nil for removed ones.
        var mapping = [Int?](repeating: nil, count: original.count)
        var next = 0
        for (position, track) in original.enumerated() where !uniqueIDs.contains(track.uniqueID) {
            mapping[position] = next
            next += 1
        }
        let survivors = original.filter { !uniqueIDs.contains($0.uniqueID) }
        guard survivors.count == next else {
            throw TrackRemovalError.countMismatch(expected: next, got: survivors.count)
        }

        // Album records nothing points to after the removal. The number
        // in `mhia` is stored in the record itself and does not follow from the position, so
        // throwing out an orphan does not disturb the numbering of the rest.
        //
        // The criterion is deliberately cautious - a record is thrown out only when
        // neither a number nor a name points to it. A database in which
        // field 0x120 is empty (and such databases exist) would otherwise lose
        // the whole album list on the first removal.
        let liveAlbumIndices = Set(survivors.map(\.albumRecordIndex))
        let liveAlbumTitles = Set(survivors.compactMap(\.album))

        var copy = self
        copy.sections = try sections.map { section in
            var updated = section
            switch section.content {
            case .tracks:
                updated.content = .tracks(survivors)
            case .playlists(let playlists):
                updated.content = .playlists(try playlists.map { playlist in
                    var rebuilt = playlist
                    rebuilt.entries = playlist.entries.filter { !uniqueIDs.contains($0.trackID) }
                    if playlist.isMaster {
                        rebuilt.mhods = try Self.remapping(playlist.mhods, through: mapping)
                    }
                    return rebuilt
                })
            case .albums(let albums):
                updated.content = .albums(albums.filter {
                    liveAlbumIndices.contains(UInt32($0.index)) || liveAlbumTitles.contains($0.title ?? "")
                })
            case .opaque:
                break
            }
            return updated
        }
        return copy
    }

    /// `mhia` records that no track points to - neither by number nor
    /// by name. They remain after the last track of an album is removed.
    public func orphanedAlbumRecords() -> [ITAlbum] {
        let indices = Set(tracks.map(\.albumRecordIndex))
        let titles = Set(tracks.compactMap(\.album))
        return albums.filter { !indices.contains(UInt32($0.index)) && !titles.contains($0.title ?? "") }
    }

    /// A copy without orphaned album records.
    public func removingOrphanedAlbumRecords() -> ITLibrary {
        let orphans = Set(orphanedAlbumRecords().map(\.persistentID))
        guard !orphans.isEmpty else { return self }
        var copy = self
        copy.sections = sections.map { section in
            guard case .albums(let albums) = section.content else { return section }
            var updated = section
            updated.content = .albums(albums.filter { !orphans.contains($0.persistentID) })
            return updated
        }
        return copy
    }

    /// Rewrites the browse tables and jump bars for the new track numbering.
    static func remapping(_ mhods: [Mhod], through mapping: [Int?]) throws -> [Mhod] {
        /// Positions in the table that disappeared - separately for each criterion,
        /// because each has a different permutation.
        var vanished: [UInt32: Set<Int>] = [:]

        var result = mhods.map { mhod -> Mhod in
            guard var index = BrowseIndex(mhod: mhod) else { return mhod }
            var kept: [UInt32] = []
            var gone: Set<Int> = []
            for (position, entry) in index.entries.enumerated() {
                let slot = Int(entry)
                if slot < mapping.count, let mapped = mapping[slot] {
                    kept.append(UInt32(mapped))
                } else {
                    gone.insert(position)
                }
            }
            vanished[index.criterion.rawValue] = gone
            index.entries = kept
            return index.mhod()
        }

        result = result.map { mhod -> Mhod in
            guard var jump = AlphabetJumpTable(mhod: mhod),
                  let gone = vanished[jump.criterion.rawValue] else { return mhod }
            var start = 0
            jump.entries = jump.entries.map { entry in
                let removed = entry.range.reduce(0) { $0 + (gone.contains($1) ? 1 : 0) }
                var updated = entry
                updated.start = UInt32(start)
                updated.count = UInt32(max(0, Int(entry.count) - removed))
                start += Int(updated.count)
                return updated
            }
            // Letters that lost all their tracks disappear from the bar.
            jump.entries.removeAll { $0.count == 0 }
            var running = 0
            jump.entries = jump.entries.map { entry in
                var updated = entry
                updated.start = UInt32(running)
                running += Int(entry.count)
                return updated
            }
            return jump.mhod()
        }
        return result
    }
}
