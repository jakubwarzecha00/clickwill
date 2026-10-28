import Foundation

/// Assembles `iTunesDB` back into bytes.
///
/// The rule that the safety of the whole app depends on: every record goes back
/// to disk as **its own original bytes**, into which we insert only the fields we
/// really know how to interpret. The format has plenty of undocumented fields, and this
/// approach lets them pass through the write untouched instead of being zeroed
/// when a record is assembled from scratch.
///
/// Lengths and child counts are recalculated, not copied. If the recalculation
/// yields the same values as the original, we understand the semantics of the fields -
/// and that is exactly what the round-trip test checks.
public enum ITunesDBWriter {

    /// Assembles an unsigned database.
    public static func serialize(_ library: ITLibrary) -> Data {
        var sections: [UInt8] = []
        for section in library.sections { sections += encode(section) }

        var header = library.rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + sections.count))
        header.set(MhbdLayout.sectionCount, UInt32(library.sections.count))
        header.set(MhbdLayout.version, library.version)
        header.set(MhbdLayout.databaseID, library.databaseID)
        return Data(header + sections)
    }

    // MARK: - Sections

    private static func encode(_ section: ITSection) -> [UInt8] {
        var children: [UInt8] = []
        var childCount = 0

        switch section.content {
        case .tracks(let tracks):
            childCount = tracks.count
            for track in tracks { children += encode(track) }
        case .playlists(let playlists):
            childCount = playlists.count
            for playlist in playlists { children += encode(playlist) }
        case .albums(let albums):
            childCount = albums.count
            for album in albums { children += encode(album) }
        case .opaque(let payload):
            var header = section.rawHeader
            header.set(RecordLayout.totalLength, UInt32(header.count + payload.count))
            return header + payload
        }

        var list = section.listRawHeader
        list.set(RecordLayout.listChildCount, UInt32(childCount))

        var header = section.rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + list.count + children.count))
        header.set(MhsdLayout.type, section.type)
        return header + list + children
    }

    // MARK: - Tracks

    private static func encode(_ track: ITTrack) -> [UInt8] {
        let children = track.mhods.flatMap(encode)
        var header = track.rawHeader

        header.set(RecordLayout.totalLength, UInt32(header.count + children.count))
        header.set(MhitLayout.mhodCount, UInt32(track.mhods.count))
        header.set(MhitLayout.uniqueID, track.uniqueID)
        header.set(MhitLayout.rating, track.rating)
        header.set(MhitLayout.sizeBytes, track.sizeBytes)
        header.set(MhitLayout.durationMilliseconds, track.durationMilliseconds)
        header.set(MhitLayout.trackNumber, track.trackNumber)
        header.set(MhitLayout.totalTracks, track.totalTracks)
        header.set(MhitLayout.year, track.year)
        header.set(MhitLayout.bitRate, track.bitRate)
        header.set(MhitLayout.sampleRate, track.rawSampleRate)
        header.set(MhitLayout.playCount, track.playCount)
        header.set(MhitLayout.lastPlayed, MacTime.value(from: track.lastPlayed))
        header.set(MhitLayout.discNumber, track.discNumber)
        header.set(MhitLayout.totalDiscs, track.totalDiscs)
        header.set(MhitLayout.dateAdded, MacTime.value(from: track.dateAdded))
        header.set(MhitLayout.persistentID, track.persistentID)
        header.set(MhitLayout.artworkCount, track.embeddedArtworkCount)
        header.set(MhitLayout.artworkSourceSize, track.embeddedArtworkSize)
        return header + children
    }

    // MARK: - Playlists

    private static func encode(_ playlist: ITPlaylist) -> [UInt8] {
        let mhods = playlist.mhods.flatMap(encode)
        let entries = playlist.entries.flatMap(encode)

        var header = playlist.rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + mhods.count + entries.count))
        header.set(MhypLayout.mhodCount, UInt32(playlist.mhods.count))
        header.set(MhypLayout.entryCount, UInt32(playlist.entries.count))
        header.set(MhypLayout.isMaster, playlist.isMaster ? 1 : 0)
        header.set(MhypLayout.persistentID, playlist.persistentID)
        return header + mhods + entries
    }

    private static func encode(_ entry: ITPlaylistEntry) -> [UInt8] {
        let children = entry.mhods.flatMap(encode)
        var header = entry.rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + children.count))
        header.set(MhipLayout.mhodCount, UInt32(entry.mhods.count))
        header.set(MhipLayout.order, entry.order)
        header.set(MhipLayout.trackID, entry.trackID)
        return header + children
    }

    // MARK: - Albums

    private static func encode(_ album: ITAlbum) -> [UInt8] {
        let children = album.mhods.flatMap(encode)
        var header = album.rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + children.count))
        header.set(MhiaLayout.mhodCount, UInt32(album.mhods.count))
        header.set(MhiaLayout.index, album.index)
        header.set(MhiaLayout.persistentID, album.persistentID)
        return header + children
    }

    // MARK: - mhod

    private static func encode(_ mhod: Mhod) -> [UInt8] {
        var header = mhod.rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + mhod.rawBody.count))
        header.set(MhodLayout.type, mhod.type.rawValue)
        return header + mhod.rawBody
    }
}
