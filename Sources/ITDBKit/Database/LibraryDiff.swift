import Foundation

/// Exactly what differs between two libraries - at the level of tracks and their fields.
///
/// Used by the backups screen. A backup does not store a list of changes, but each
/// is a full database, so comparing two consecutive backups says exactly what
/// the write between them changed, and comparing a backup with the current state - what
/// restoring it would undo. It also works for backups made before this code existed.
///
/// Tracks are matched by `persistentID`: it follows a track across writes,
/// unlike `uniqueID`, which is an index within one database.
///
/// **Play counts are skipped on purpose.** They change with every write,
/// because the iPod increments them itself, and they would flood every comparison with
/// hundreds of "changes" nobody made.
public struct LibraryDiff: Sendable {

    public struct Song: Sendable, Hashable {
        public let persistentID: UInt64
        public let title: String
        public let artist: String
        public let album: String
        public let trackNumber: UInt32
    }

    public enum Field: String, Sendable, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case albumArtist = "Album artist"
        case genre = "Genre"
        case composer = "Composer"
        case year = "Year"
        case trackNumber = "Track number"
        case discNumber = "Disc number"
        case compilation = "Compilation"
        case audioFile = "Audio file"
        case cover = "Cover"
    }

    public struct Edit: Sendable, Hashable {
        public let song: Song
        public let field: Field
        public let before: String
        public let after: String
    }

    /// Tracks present in the newer library and absent from the older one.
    public let added: [Song]
    /// Tracks present in the older one and absent from the newer one.
    public let removed: [Song]
    public let edits: [Edit]
    /// Whether the album order in the iPod menu changed.
    public let albumOrderChanged: Bool

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && edits.isEmpty && !albumOrderChanged }

    public init(from old: ITLibrary, to new: ITLibrary) {
        let before = Dictionary(old.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })
        let after = Dictionary(new.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })

        added = new.tracks.filter { before[$0.persistentID] == nil }.map(Self.song)
        removed = old.tracks.filter { after[$0.persistentID] == nil }.map(Self.song)

        var edits: [Edit] = []
        for track in new.tracks {
            guard let previous = before[track.persistentID] else { continue }
            let song = Self.song(track)
            for field in Field.allCases {
                let (was, now) = (Self.value(field, of: previous), Self.value(field, of: track))
                if was != now { edits.append(Edit(song: song, field: field, before: was, after: now)) }
            }
        }
        self.edits = edits
        albumOrderChanged = Self.albumOrder(of: old) != Self.albumOrder(of: new)
    }

    // MARK: - Grouping for display

    /// Changes of one album.
    public struct AlbumChanges: Sendable, Identifiable {
        public var id: String { album }
        public let album: String
        public let artist: String
        public let added: [Song]
        public let removed: [Song]
        /// Collapsed changes: the same change on many tracks of an album is
        /// one item with a count, not a dozen identical lines.
        public let edits: [GroupedEdit]

        public var changeCount: Int { added.count + removed.count + edits.reduce(0) { $0 + $1.songs.count } }
    }

    public struct GroupedEdit: Sendable, Hashable {
        public let field: Field
        public let before: String
        public let after: String
        public let songs: [Song]
    }

    /// Changes grouped by album, alphabetically.
    public var albums: [AlbumChanges] {
        var keys = Set<String>()
        added.forEach { keys.insert($0.album) }
        removed.forEach { keys.insert($0.album) }
        edits.forEach { keys.insert($0.song.album) }

        return keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { album in
            let edited = edits.filter { $0.song.album == album }
            var grouped: [GroupedEdit] = []
            var order: [String] = []
            var bucket: [String: (Field, String, String, [Song])] = [:]
            for edit in edited {
                let key = "\(edit.field.rawValue)\u{1F}\(edit.before)\u{1F}\(edit.after)"
                if bucket[key] == nil { order.append(key); bucket[key] = (edit.field, edit.before, edit.after, []) }
                bucket[key]?.3.append(edit.song)
            }
            for key in order {
                if let (field, before, after, songs) = bucket[key] {
                    grouped.append(GroupedEdit(field: field, before: before, after: after,
                                               songs: songs.sorted { $0.trackNumber < $1.trackNumber }))
                }
            }
            let sample = (added + removed).first { $0.album == album } ?? edited.first?.song
            return AlbumChanges(
                album: album, artist: sample?.artist ?? "",
                added: added.filter { $0.album == album }.sorted { $0.trackNumber < $1.trackNumber },
                removed: removed.filter { $0.album == album }.sorted { $0.trackNumber < $1.trackNumber },
                edits: grouped)
        }
    }

    // MARK: - Helpers

    public static func song(_ track: ITTrack) -> Song {
        Song(persistentID: track.persistentID, title: track.title ?? "Untitled",
             artist: track.albumArtist ?? track.artist ?? "", album: track.album ?? "",
             trackNumber: track.trackNumber)
    }

    static func value(_ field: Field, of track: ITTrack) -> String {
        switch field {
        case .title: return track.title ?? ""
        case .artist: return track.artist ?? ""
        case .album: return track.album ?? ""
        case .albumArtist: return track.albumArtist ?? ""
        case .genre: return track.genre ?? ""
        case .composer: return track.composer ?? ""
        case .year: return track.year == 0 ? "" : "\(track.year)"
        case .trackNumber: return track.trackNumber == 0 ? "" : "\(track.trackNumber)"
        case .discNumber: return track.discNumber == 0 ? "" : "\(track.discNumber)"
        case .compilation: return track.isCompilation ? "yes" : "no"
        // File: path and size together. The path alone would miss a replacement
        // in the same place, the size alone - a move.
        case .audioFile:
            let name = (track.relativePath ?? "").split(separator: ":").last.map(String.init) ?? ""
            return name.isEmpty ? "" : "\(name) · \(ByteCountFormatter.string(fromByteCount: Int64(track.sizeBytes), countStyle: .file))"
        // Artwork: which image the track points to, and its source size.
        case .cover:
            return track.artworkIdentifier == 0 && track.embeddedArtworkSize == 0
                ? "" : "image \(track.artworkIdentifier)/\(track.embeddedArtworkSize)"
        }
    }

    /// Album order as the iPod shows it in the menu.
    static func albumOrder(of library: ITLibrary) -> [String] {
        guard let index = library.browseIndex(.album) else { return [] }
        var seen = Set<String>()
        var order: [String] = []
        for entry in index.entries where Int(entry) < library.tracks.count {
            let album = library.tracks[Int(entry)].album ?? ""
            if seen.insert(album).inserted { order.append(album) }
        }
        return order
    }
}
