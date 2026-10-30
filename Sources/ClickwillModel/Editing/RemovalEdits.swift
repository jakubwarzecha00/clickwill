import Foundation
import ITDBKit

/// Removal: a track, a whole album, surplus copies of the same song.
///
/// The record disappears from the library right away, the file from the iPod only after a successful write -
/// and only a file that may be deleted (`ChangeSet.queueFiles`). The same rule
/// applies to `ipodctl remove`.
extension LibraryEditor {

    /// Removes a track from the database. `archive`: the folder for a copy of the file before deletion.
    mutating func deleteTrack(_ track: TrackRow, in album: AlbumCard, keepCopiesIn archive: URL?) throws {
        let removed = library.tracks.filter { $0.uniqueID == track.id }
        try refuseRemoval(of: removed)
        library = try library.removingTracks(uniqueIDs: [track.id])
        let queued = changes.queueFiles(of: removed, keeping: library, paths: paths, files: files, keepCopiesIn: archive)
        recordChange(.trackDeleted(album: title(of: album), track: track.displayTitle, fileOnDisk: !queued.isEmpty))
    }

    /// Removes a whole album together with its files. One log item instead of
    /// a dozen - and one place where the user can be told
    /// what a backup will not undo.
    ///
    /// `archive` is the folder for copies of the files. Without it the music disappears from the iPod
    /// for good: a backup holds the database and artwork, not the audio files.
    /// Returns the number of tracks removed.
    mutating func deleteAlbum(_ album: AlbumCard, keepCopiesIn archive: URL?) throws -> Int {
        guard let album = current(album) else { return 0 }
        let records = records(of: album)
        guard !records.isEmpty else { return 0 }
        try refuseRemoval(of: records)
        library = try library.removingTracks(uniqueIDs: Set(records.map(\.uniqueID)))
        let queued = changes.queueFiles(of: records, keeping: library, paths: paths, files: files, keepCopiesIn: archive)
        recordChange(.albumDeleted(album: album.displayTitle, artist: album.displayArtist,
                                   tracks: records.count, files: queued.count, copiesSaved: archive?.path))
        return records.count
    }

    /// Merges each group into one song: the `keep` copy stays, the others
    /// disappear from the database, and their files from the iPod after the write. The copy that stays
    /// takes over the sum of plays, the higher rating, the later playback,
    /// the earlier date added, the places in playlists and - when needed -
    /// the album artwork in Cover Flow.
    ///
    /// `archive` is the folder for copies of the removed files, as when removing an album.
    /// Returns the number of copies removed.
    mutating func mergeDuplicates(_ groups: [DuplicateGroup], keepCopiesIn archive: URL?) throws -> Int {
        let byID = Dictionary(library.tracks.map { ($0.uniqueID, $0) }, uniquingKeysWith: { first, _ in first })

        var redirects: [UInt32: UInt32] = [:]
        var owners: [UInt64: UInt64] = [:]
        var merged: [UInt32: ITTrack] = [:]
        for group in groups {
            guard var keep = byID[group.keep.id], redirects[keep.uniqueID] == nil else { continue }
            for copy in group.remove where copy.id != keep.uniqueID && redirects[copy.id] == nil && merged[copy.id] == nil {
                guard let gone = byID[copy.id] else { continue }
                redirects[gone.uniqueID] = keep.uniqueID
                owners[gone.persistentID] = keep.persistentID
                keep.playCount += gone.playCount
                keep.rating = max(keep.rating, gone.rating)
                if let played = gone.lastPlayed, played > (keep.lastPlayed ?? .distantPast) { keep.lastPlayed = played }
                if let added = gone.dateAdded, added < (keep.dateAdded ?? .distantFuture) { keep.dateAdded = added }
            }
            merged[keep.uniqueID] = keep
        }
        guard !redirects.isEmpty else { return 0 }
        let removed = Set(redirects.keys)
        try refuseRemoval(of: removed.compactMap { byID[$0] })

        library = try library
            .mappingTracks { merged[$0.uniqueID] ?? $0 }
            .redirectingPlaylistEntries(redirects)
            .redirectingAlbumArtworkOwners(owners)
            .removingTracks(uniqueIDs: removed)
        let queued = changes.queueFiles(of: removed.sorted().compactMap { byID[$0] }, keeping: library,
                                        paths: paths, files: files, keepCopiesIn: archive)

        changes.redirect(playCounts: redirects, artworkOwners: owners)

        // Preview: the album artwork must stay in place even before the write.
        artwork = artwork?.reowning(owners)
        reownCovers(owners)

        recordChange(.duplicatesMerged(songs: removed.count, files: queued.count, copiesSaved: archive?.path))
        return removed.count
    }
}
