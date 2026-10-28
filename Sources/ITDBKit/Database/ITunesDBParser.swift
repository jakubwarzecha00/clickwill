import Foundation

/// Reads the whole `iTunesDB`, keeping the original bytes of every record.
///
/// The format consists of nested records with a four-character signature.
/// There are two header shapes, and mixing them up misaligns the whole file:
///
/// - **containers** (`mhbd`, `mhsd`, `mhit`, `mhyp`, `mhip`, `mhia`, `mhod`)
///   have the total length at offset 8, including children;
/// - **lists** (`mhlt`, `mhlp`, `mhla`) have the number of children there, and the children
///   follow the list header, within the parent's area.
public enum ITunesDBParser {

    public static func parse(_ data: Data) throws -> ITLibrary {
        let reader = ByteReader(data)
        guard try reader.signature(at: 0) == "mhbd" else { throw ITDBError.notAnITunesDB }

        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: 0))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: 0))
        guard totalLength == reader.count else {
            throw ITDBError.lengthMismatch(declared: totalLength, actual: reader.count)
        }

        let sectionCount = Int(try reader.value(MhbdLayout.sectionCount, inRecordAt: 0))
        var sections: [ITSection] = []
        var offset = headerLength
        for _ in 0..<sectionCount {
            let (section, next) = try parseSection(reader, at: offset)
            sections.append(section)
            offset = next
        }

        return ITLibrary(
            version: try reader.value(MhbdLayout.version, inRecordAt: 0),
            databaseID: try reader.value(MhbdLayout.databaseID, inRecordAt: 0),
            hashingScheme: try reader.value(MhbdLayout.hashingScheme, inRecordAt: 0),
            sections: sections,
            rawHeader: try reader.slice(0..<headerLength),
            sourceByteCount: reader.count
        )
    }

    /// Just the iPod's name (the master playlist title), without reading tracks.
    /// For the list of connected iPods: a full read of a Classic database takes
    /// fractions of a second per iPod, and only one string is needed here.
    public static func deviceName(in data: Data) throws -> String? {
        let reader = ByteReader(data)
        guard try reader.signature(at: 0) == "mhbd" else { throw ITDBError.notAnITunesDB }
        var offset = Int(try reader.value(RecordLayout.headerLength, inRecordAt: 0))
        for _ in 0..<Int(try reader.value(MhbdLayout.sectionCount, inRecordAt: 0)) {
            try expect("mhsd", reader, at: offset)
            let sectionLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
            let listOffset = offset + Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
            guard sectionLength > 0 else { return nil }
            if try reader.signature(at: listOffset) == "mhlp" {
                var cursor = listOffset + Int(try reader.value(RecordLayout.headerLength, inRecordAt: listOffset))
                for _ in 0..<Int(try reader.value(RecordLayout.listChildCount, inRecordAt: listOffset)) {
                    try expect("mhyp", reader, at: cursor)
                    if try reader.value(MhypLayout.isMaster, inRecordAt: cursor) == 1 {
                        let (mhods, _) = try parseMhods(reader, at: cursor + Int(try reader.value(RecordLayout.headerLength, inRecordAt: cursor)),
                                                        count: Int(try reader.value(MhypLayout.mhodCount, inRecordAt: cursor)))
                        return mhods.first { $0.type == .title }?.text
                    }
                    let playlistLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: cursor))
                    guard playlistLength > 0 else { return nil }
                    cursor += playlistLength
                }
            }
            offset += sectionLength
        }
        return nil
    }

    // MARK: - Sections

    private static func parseSection(_ reader: ByteReader, at offset: Int) throws -> (ITSection, Int) {
        try expect("mhsd", reader, at: offset)
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let type = try reader.value(MhsdLayout.type, inRecordAt: offset)

        let listOffset = offset + headerLength
        let sectionEnd = offset + totalLength

        // A type we do not know is not a read error: we take it whole
        // and hand it back on write. Known types must still carry their list -
        // a different signature in them is damage, not a new format.
        guard ITSection.Kind(rawValue: type) != nil else {
            let section = ITSection(
                type: type,
                content: .opaque(try reader.slice(listOffset..<sectionEnd)),
                rawHeader: try reader.slice(offset..<(offset + headerLength)),
                listRawHeader: []
            )
            return (section, sectionEnd)
        }

        let listSignature = try reader.signature(at: listOffset)
        let listHeaderLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: listOffset))
        let childCount = Int(try reader.value(RecordLayout.listChildCount, inRecordAt: listOffset))

        var cursor = listOffset + listHeaderLength
        let content: ITSection.Content

        switch listSignature {
        case "mhlt":
            var tracks: [ITTrack] = []
            tracks.reserveCapacity(childCount)
            for _ in 0..<childCount {
                let (track, next) = try parseTrack(reader, at: cursor)
                tracks.append(track)
                cursor = next
            }
            content = .tracks(tracks)

        case "mhlp":
            var playlists: [ITPlaylist] = []
            playlists.reserveCapacity(childCount)
            for _ in 0..<childCount {
                let (playlist, next) = try parsePlaylist(reader, at: cursor)
                playlists.append(playlist)
                cursor = next
            }
            content = .playlists(playlists)

        case "mhla":
            var albums: [ITAlbum] = []
            albums.reserveCapacity(childCount)
            for _ in 0..<childCount {
                let (album, next) = try parseAlbum(reader, at: cursor)
                albums.append(album)
                cursor = next
            }
            content = .albums(albums)

        default:
            throw ITDBError.unexpectedSignature(expected: "mhlt/mhlp/mhla", found: listSignature, offset: listOffset)
        }

        let section = ITSection(
            type: type,
            content: content,
            rawHeader: try reader.slice(offset..<(offset + headerLength)),
            listRawHeader: try reader.slice(listOffset..<(listOffset + listHeaderLength))
        )
        return (section, sectionEnd)
    }

    // MARK: - Tracks

    private static func parseTrack(_ reader: ByteReader, at offset: Int) throws -> (ITTrack, Int) {
        try expect("mhit", reader, at: offset)
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let mhodCount = Int(try reader.value(MhitLayout.mhodCount, inRecordAt: offset))

        let (mhods, _) = try parseMhods(reader, at: offset + headerLength, count: mhodCount)
        var fields: [MhodType: String] = [:]
        for mhod in mhods {
            if let text = mhod.text { fields[mhod.type] = text }
        }

        let track = ITTrack(
            uniqueID: try reader.value(MhitLayout.uniqueID, inRecordAt: offset),
            fields: fields,
            mhods: mhods,
            sizeBytes: try reader.value(MhitLayout.sizeBytes, inRecordAt: offset),
            durationMilliseconds: try reader.value(MhitLayout.durationMilliseconds, inRecordAt: offset),
            trackNumber: try reader.value(MhitLayout.trackNumber, inRecordAt: offset),
            totalTracks: try reader.value(MhitLayout.totalTracks, inRecordAt: offset),
            year: try reader.value(MhitLayout.year, inRecordAt: offset),
            bitRate: try reader.value(MhitLayout.bitRate, inRecordAt: offset),
            rawSampleRate: try reader.value(MhitLayout.sampleRate, inRecordAt: offset),
            discNumber: try reader.value(MhitLayout.discNumber, inRecordAt: offset),
            totalDiscs: try reader.value(MhitLayout.totalDiscs, inRecordAt: offset),
            playCount: try reader.value(MhitLayout.playCount, inRecordAt: offset),
            rating: try reader.value(MhitLayout.rating, inRecordAt: offset),
            dateAdded: MacTime.date(from: try reader.value(MhitLayout.dateAdded, inRecordAt: offset)),
            lastPlayed: MacTime.date(from: try reader.value(MhitLayout.lastPlayed, inRecordAt: offset)),
            persistentID: try reader.value(MhitLayout.persistentID, inRecordAt: offset),
            embeddedArtworkCount: try reader.value(MhitLayout.artworkCount, inRecordAt: offset),
            embeddedArtworkSize: try reader.value(MhitLayout.artworkSourceSize, inRecordAt: offset),
            rawHeader: try reader.slice(offset..<(offset + headerLength))
        )
        return (track, offset + totalLength)
    }

    // MARK: - Playlists

    private static func parsePlaylist(_ reader: ByteReader, at offset: Int) throws -> (ITPlaylist, Int) {
        try expect("mhyp", reader, at: offset)
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let mhodCount = Int(try reader.value(MhypLayout.mhodCount, inRecordAt: offset))
        let entryCount = Int(try reader.value(MhypLayout.entryCount, inRecordAt: offset))

        let (mhods, afterMhods) = try parseMhods(reader, at: offset + headerLength, count: mhodCount)

        var entries: [ITPlaylistEntry] = []
        entries.reserveCapacity(entryCount)
        var cursor = afterMhods
        for _ in 0..<entryCount {
            let (entry, next) = try parseEntry(reader, at: cursor)
            entries.append(entry)
            cursor = next
        }

        let playlist = ITPlaylist(
            name: mhods.first { $0.type == .title }?.text,
            isMaster: try reader.value(MhypLayout.isMaster, inRecordAt: offset) == 1,
            persistentID: try reader.value(MhypLayout.persistentID, inRecordAt: offset),
            entries: entries,
            mhods: mhods,
            rawHeader: try reader.slice(offset..<(offset + headerLength))
        )
        return (playlist, offset + totalLength)
    }

    private static func parseEntry(_ reader: ByteReader, at offset: Int) throws -> (ITPlaylistEntry, Int) {
        try expect("mhip", reader, at: offset)
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let mhodCount = Int(try reader.value(MhipLayout.mhodCount, inRecordAt: offset))
        let (mhods, _) = try parseMhods(reader, at: offset + headerLength, count: mhodCount)

        let entry = ITPlaylistEntry(
            trackID: try reader.value(MhipLayout.trackID, inRecordAt: offset),
            order: try reader.value(MhipLayout.order, inRecordAt: offset),
            mhods: mhods,
            rawHeader: try reader.slice(offset..<(offset + headerLength))
        )
        return (entry, offset + totalLength)
    }

    // MARK: - Albums

    private static func parseAlbum(_ reader: ByteReader, at offset: Int) throws -> (ITAlbum, Int) {
        try expect("mhia", reader, at: offset)
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let mhodCount = Int(try reader.value(MhiaLayout.mhodCount, inRecordAt: offset))
        let (mhods, _) = try parseMhods(reader, at: offset + headerLength, count: mhodCount)

        func text(_ type: MhodType) -> String? { mhods.first { $0.type == type }?.text }

        let album = ITAlbum(
            index: try reader.value(MhiaLayout.index, inRecordAt: offset),
            persistentID: try reader.value(MhiaLayout.persistentID, inRecordAt: offset),
            title: text(.albumTitle),
            artist: text(.albumArtistName),
            sortArtist: text(.albumSortArtist),
            mhods: mhods,
            rawHeader: try reader.slice(offset..<(offset + headerLength))
        )
        return (album, offset + totalLength)
    }

    // MARK: - mhod

    private static func parseMhods(
        _ reader: ByteReader, at offset: Int, count: Int
    ) throws -> ([Mhod], Int) {
        var mhods: [Mhod] = []
        mhods.reserveCapacity(count)
        var cursor = offset
        for _ in 0..<count {
            let (mhod, next) = try parseMhod(reader, at: cursor)
            mhods.append(mhod)
            cursor = next
        }
        return (mhods, cursor)
    }

    private static func parseMhod(_ reader: ByteReader, at offset: Int) throws -> (Mhod, Int) {
        try expect("mhod", reader, at: offset)
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let type = MhodType(rawValue: try reader.value(MhodLayout.type, inRecordAt: offset))

        let bodyStart = offset + headerLength
        let bodyEnd = offset + totalLength
        let body = try reader.slice(bodyStart..<bodyEnd)

        var text: String?
        let textStart = bodyStart + MhodLayout.Text.start
        if type.carriesText, body.count >= MhodLayout.Text.start {
            let byteCount = Int(try reader.value(MhodLayout.Text.byteCount, inRecordAt: bodyStart))
            let encoding = try reader.value(MhodLayout.Text.encoding, inRecordAt: bodyStart)
            if byteCount > 0, textStart + byteCount <= bodyEnd {
                if encoding == 1 {
                    text = try reader.utf16String(at: textStart, byteCount: byteCount)
                } else {
                    text = String(
                        decoding: try reader.slice(textStart..<(textStart + byteCount)),
                        as: UTF8.self
                    )
                }
            } else if byteCount == 0 {
                text = ""
            }
        }

        let mhod = Mhod(
            type: type,
            text: text,
            rawHeader: try reader.slice(offset..<bodyStart),
            rawBody: body
        )
        return (mhod, bodyEnd)
    }

    // MARK: - Helpers

    private static func expect(_ signature: String, _ reader: ByteReader, at offset: Int) throws {
        let found = try reader.signature(at: offset)
        guard found == signature else {
            throw ITDBError.unexpectedSignature(expected: signature, found: found, offset: offset)
        }
    }
}
