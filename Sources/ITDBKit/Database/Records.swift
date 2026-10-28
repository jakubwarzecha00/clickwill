import Foundation

/// A container for text or auxiliary data. Always keeps the original bytes,
/// so that the writer can reproduce the record exactly as it found it.
public struct Mhod: Sendable {
    public let type: MhodType
    /// The text, if the type carries one. `nil` for binary data.
    public let text: String?

    /// 24 header bytes, exactly as in the file.
    public let rawHeader: [UInt8]
    /// Everything after the header, exactly as in the file.
    public let rawBody: [UInt8]

    public var byteCount: Int { rawHeader.count + rawBody.count }
}

/// A track - an `mhit` record together with its text fields.
public struct ITTrack: Sendable, Identifiable {
    /// Set only when creating a new record - an existing track never
    /// changes its identifier, because the browse tables hold it.
    public internal(set) var uniqueID: UInt32
    public var id: UInt32 { uniqueID }

    public var fields: [MhodType: String]
    public var mhods: [Mhod]

    public internal(set) var sizeBytes: UInt32
    public internal(set) var durationMilliseconds: UInt32
    public var trackNumber: UInt32
    public var totalTracks: UInt32
    public var year: UInt32
    public internal(set) var bitRate: UInt32
    /// The `MhitLayout.sampleRate` field in its original form. The sample rate sits
    /// in the upper 16 bits, but we keep the whole value so the write does not lose the lower bits.
    public internal(set) var rawSampleRate: UInt32
    public var discNumber: UInt32
    public var totalDiscs: UInt32
    public var playCount: UInt32
    public var rating: UInt8
    public var dateAdded: Date?
    public var lastPlayed: Date?
    public internal(set) var persistentID: UInt64
    /// Number of artwork images linked to the track (`MhitLayout.artworkCount`, 16 bits).
    public internal(set) var embeddedArtworkCount: UInt16
    /// Artwork source size in bytes (`MhitLayout.artworkSourceSize`).
    public internal(set) var embeddedArtworkSize: UInt32

    public internal(set) var rawHeader: [UInt8]

    public var title: String? { fields[.title] }
    public var album: String? { fields[.album] }
    public var artist: String? { fields[.artist] }
    public var albumArtist: String? { fields[.albumArtist] }
    public var genre: String? { fields[.genre] }
    public var composer: String? { fields[.composer] }
    public var sortTitle: String? { fields[.sortTitle] }
    public var sortAlbum: String? { fields[.sortAlbum] }
    public var sortArtist: String? { fields[.sortArtist] }
    public var sortAlbumArtist: String? { fields[.sortAlbumArtist] }

    /// The artist used for grouping albums - the album artist, or the artist when that is missing.
    public var effectiveAlbumArtist: String { albumArtist ?? artist ?? "" }

    /// Sample rate stored as a `Float` (`MhitLayout.sampleRateFloat`) -
    /// the second place where iTunes keeps it. Established on the device:
    /// 0x472c4400 = 44100.0, 0x473b8000 = 48000.0, always consistent with the upper
    /// bits of `rawSampleRate`.
    public var sampleRateFloat: Float {
        get { rawHeader[MhitLayout.sampleRateFloat].map(Float.init(bitPattern:)) ?? 0 }
        set { rawHeader.set(MhitLayout.sampleRateFloat, newValue.bitPattern) }
    }

    /// Second record of the file size (`MhitLayout.sizeBytesSecondary`). Established
    /// on the device: equal to `sizeBytes` for all 1603 tracks.
    public var sizeBytesSecondary: UInt32 {
        get { rawHeader[MhitLayout.sizeBytesSecondary] ?? 0 }
        set { rawHeader.set(MhitLayout.sizeBytesSecondary, newValue) }
    }

    /// Album record index (`mhia` 0x10, `MhitLayout.albumRecordIndex`).
    /// Established on the device: 1603/1603 tracks point to the `mhia` with the same
    /// title.
    public var albumRecordIndex: UInt32 {
        get { rawHeader[MhitLayout.albumRecordIndex] ?? 0 }
        set { rawHeader.set(MhitLayout.albumRecordIndex, newValue) }
    }

    /// Compilation flag (`MhitLayout.compilation`). On the iPod Classic it moves
    /// the album out of the artist's group into a separate "Compilations" group at the end of Cover Flow.
    public var isCompilation: Bool {
        get { (rawHeader[MhitLayout.compilation] ?? 0) != 0 }
        set { rawHeader.set(MhitLayout.compilation, newValue ? 1 : 0) }
    }

    /// The key by which we group albums **in our interface**. Falls back
    /// to the artist, so that two different albums with the same name do not merge.
    public var albumKey: AlbumKey { AlbumKey(album: album ?? "", albumArtist: effectiveAlbumArtist) }

    /// The key by which the **device** merges tracks under one cover.
    ///
    /// Deliberately without the artist fallback - the iPod looks only at the sort fields,
    /// and their absence is itself a value shared by the whole album.
    ///
    /// Both fields are compared as a **pair**, not through `??`. On the test database
    /// merging them gave the same value for a track that actually splits the album:
    /// twenty-four tracks had sort artist "Weeknd" without a sort album artist,
    /// and one had sort album artist "Weeknd" - indistinguishable after merging.
    ///
    /// Which of the two fields really decides cannot be settled on one
    /// library - both split the same way. So we treat any inconsistency
    /// as a reason to repair.
    public var deviceGroupingKey: DeviceGroupingKey {
        DeviceGroupingKey(sortAlbumArtist: sortAlbumArtist, sortArtist: sortArtist)
    }

    /// A path in the database has the form `:iPod_Control:Music:F03:UOLJ.m4a` - colons
    /// instead of slashes, with a leading separator marking the volume root.
    public var relativePath: String? {
        fields[.location].map(Self.filesystemPath(fromDatabaseLocation:))
    }

    /// Converts a path from the database form to a path relative to the volume.
    public static func filesystemPath(fromDatabaseLocation location: String) -> String {
        var path = location.replacingOccurrences(of: ":", with: "/")
        while path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    /// The inverse of `filesystemPath(fromDatabaseLocation:)` - needed when writing.
    public static func databaseLocation(fromFilesystemPath path: String) -> String {
        var relative = path
        while relative.hasPrefix("/") { relative.removeFirst() }
        return ":" + relative.replacingOccurrences(of: "/", with: ":")
    }

    /// The track's file - only inside `iPod_Control/Music`. A location with `..`
    /// or leading through a link outside the iPod gives `nil`, i.e. a track without a file
    /// (security audit 0.1.3).
    public func fileURL(on paths: IPodPaths) -> URL? {
        guard let relative = relativePath else { return nil }
        return paths.musicFile(relative)
    }

    public var sampleRate: UInt32 { rawSampleRate >> 16 }
    public var duration: TimeInterval { TimeInterval(durationMilliseconds) / 1000 }

    /// Whether the audio file carries its own artwork. This is different from the thumbnail in `ArtworkDB`:
    /// the artwork database is the iPod's cache and usually keeps one image per album.
    public var hasEmbeddedArtwork: Bool { embeddedArtworkCount > 0 }
}

/// The pair of sort fields by which the device tells covers apart.
public struct DeviceGroupingKey: Hashable, Sendable {
    public let sortAlbumArtist: String?
    public let sortArtist: String?

    public var description: String {
        switch (sortAlbumArtist, sortArtist) {
        case (nil, nil): return "(no sort fields)"
        case (let albumArtist?, nil): return "sort album artist '\(albumArtist)'"
        case (nil, let artist?): return "sort artist '\(artist)'"
        case (let albumArtist?, let artist?): return "sort album artist '\(albumArtist)', sort artist '\(artist)'"
        }
    }
}

public struct AlbumKey: Hashable, Sendable, Codable {
    public let album: String
    public let albumArtist: String
    public init(album: String, albumArtist: String) {
        self.album = album
        self.albumArtist = albumArtist
    }
}

/// A playlist item - an `mhip` record. The order is stored here explicitly,
/// unlike albums, which the iPod sorts itself.
public struct ITPlaylistEntry: Sendable {
    public var trackID: UInt32
    public var order: UInt32
    public let mhods: [Mhod]
    public let rawHeader: [UInt8]
}

/// A playlist - an `mhyp` record.
public struct ITPlaylist: Sendable, Identifiable {
    public let name: String?
    public let isMaster: Bool
    public let persistentID: UInt64
    public var entries: [ITPlaylistEntry]
    public var mhods: [Mhod]
    public let rawHeader: [UInt8]

    public var id: UInt64 { persistentID }
    public var trackCount: Int { entries.count }
}

/// An entry in the album list - an `mhia` record.
///
/// Note: this list is an index maintained by iTunes and is sometimes incomplete.
/// The source of truth about albums is the track fields, not this index.
public struct ITAlbum: Sendable, Identifiable {
    public let index: UInt16
    /// Identity of the album record. Mutable, because a record that received
    /// a track identifier must be repairable - see
    /// `ITLibrary.repairingAlbumIdentities`.
    public internal(set) var persistentID: UInt64
    public let title: String?
    public let artist: String?
    public let sortArtist: String?
    public let mhods: [Mhod]
    public internal(set) var rawHeader: [UInt8]

    public var id: UInt64 { persistentID }

    /// `persistentID` of the track whose `mhii` is the album artwork
    /// (`MhiaLayout.artworkOwner`). Zero = an album without designated artwork.
    /// Established on the device: ASTROWORLD points to STARGAZING, the only track
    /// of the album with an `mhii` record.
    public var artworkOwnerPersistentID: UInt64 {
        get { rawHeader[MhiaLayout.artworkOwner] ?? 0 }
        set { rawHeader.set(MhiaLayout.artworkOwner, newValue) }
    }
}

/// A database section - an `mhsd` record. Each carries one list.
public struct ITSection: Sendable {
    public enum Kind: UInt32, Sendable {
        case tracks = 1
        case playlists = 2
        case podcasts = 3
        case albums = 4
        case smartPlaylists = 5
    }

    public enum Content: Sendable {
        case tracks([ITTrack])
        case playlists([ITPlaylist])
        case albums([ITAlbum])
        /// A section of a type we do not interpret - carried over byte for byte.
        /// On the nano 2G Finder writes a type 9 section with a 32-character
        /// text identifier instead of a list (measured).
        case opaque([UInt8])
    }

    public let type: UInt32
    public var content: Content
    public let rawHeader: [UInt8]
    /// The list header inside a section (`mhlt`, `mhlp`, `mhla`).
    public let listRawHeader: [UInt8]

    public var kind: Kind? { Kind(rawValue: type) }
}

/// The whole library read from `iTunesDB`.
public struct ITLibrary: Sendable {
    public var version: UInt32
    public let databaseID: UInt64
    public let hashingScheme: UInt16
    public var sections: [ITSection]
    public let rawHeader: [UInt8]
    /// Size of the source file - the reference point for the round-trip test.
    public let sourceByteCount: Int

    public var tracks: [ITTrack] {
        for section in sections {
            if case .tracks(let tracks) = section.content { return tracks }
        }
        return []
    }

    public var albums: [ITAlbum] {
        for section in sections {
            if case .albums(let albums) = section.content { return albums }
        }
        return []
    }

    /// Playlists from the first section that carries them.
    ///
    /// The database usually keeps them twice - in sections of type 2 and type 3 - because iTunes
    /// writes the old and the new format side by side. One copy is enough for reading,
    /// but both must be updated when writing.
    public var playlists: [ITPlaylist] {
        for section in sections {
            if case .playlists(let playlists) = section.content, !playlists.isEmpty {
                return playlists
            }
        }
        return []
    }

    public var masterPlaylist: ITPlaylist? { playlists.first { $0.isMaster } }

    /// The device name - iTunes stores it as the name of the master playlist.
    public var deviceName: String? { masterPlaylist?.name }

    /// Albums built from track fields, not from the `mhla` index.
    public func albumGroups() -> [AlbumKey: [ITTrack]] {
        Dictionary(grouping: tracks, by: \.albumKey)
    }

    /// Albums the device will show as several separate covers.
    ///
    /// Established experimentally on a real iPod, contrary to the first guess:
    /// grouping goes by the **sort fields**, not by the artist. Tracks
    /// with a featured artist in the artist field do not split the album as long as they have no
    /// sort fields of their own. That is why there is deliberately **no fallback** to the artist here -
    /// it was exactly what produced false splits.
    ///
    /// One track with a different key is enough for the album to appear twice in Cover Flow.
    public func albumsSplitOnDevice() -> [(album: String, groups: [(key: DeviceGroupingKey, tracks: [ITTrack])])] {
        Dictionary(grouping: tracks.filter { !($0.album ?? "").isEmpty }, by: { $0.album ?? "" })
            .compactMap { album, tracks in
                let groups = Dictionary(grouping: tracks) { $0.deviceGroupingKey }
                guard groups.count > 1 else { return nil }
                return (
                    album,
                    groups.map { (key: $0.key, tracks: $0.value) }
                        .sorted { $0.tracks.count > $1.tracks.count }
                )
            }
            .sorted { $0.groups.count > $1.groups.count }
    }

    /// Albums the device will show twice, because the album artist is a different
    /// name than the track artist.
    ///
    /// Established experimentally and **confirmed by a repair on hardware**: the iPod indexes
    /// such an album under both names, so it appears twice in Cover Flow,
    /// complete each time. Unifying both fields merges the covers.
    ///
    /// Variation in the artist field alone is not enough - an album with featured artists
    /// on every track, but with an empty album artist, shows up once.
    /// What decides is a mismatch between the album artist and the track artists.
    ///
    /// A rule derived from a single case, so we treat it as strong
    /// evidence, not a certainty - hence a cautious criterion: we report only
    /// when no track of the album has an artist equal to the album artist.
    public func albumsDuplicatedByArtistMismatch() -> [(album: String, albumArtist: String, artists: [String], trackCount: Int)] {
        Dictionary(grouping: tracks.filter { !($0.album ?? "").isEmpty }, by: { $0.album ?? "" })
            .compactMap { album, tracks in
                let albumArtists = Set(tracks.compactMap { $0.albumArtist }.filter { !$0.isEmpty })
                guard albumArtists.count == 1, let albumArtist = albumArtists.first else { return nil }

                let artists = Set(tracks.compactMap { $0.artist }.filter { !$0.isEmpty })
                guard !artists.isEmpty else { return nil }

                let target = albumArtist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                let related = artists.contains { artist in
                    let value = artist.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    return value == target || value.contains(target) || target.contains(value)
                }
                guard !related else { return nil }

                return (album, albumArtist, artists.sorted(), tracks.count)
            }
            .sorted { $0.album < $1.album }
    }

    /// Albums whose tracks disagree on the album artist.
    ///
    /// It does not split the album into separate covers, but it throws off the **order**: the browse
    /// table groups tracks by artist, so the album goes in blocks instead of
    /// by track number.
    public func albumsWithMixedOrder() -> [(album: String, blocks: [(artist: String, tracks: [ITTrack])])] {
        Dictionary(grouping: tracks.filter { !($0.album ?? "").isEmpty }, by: { $0.album ?? "" })
            .compactMap { album, tracks in
                let blocks = Dictionary(grouping: tracks) { $0.albumArtist ?? "" }
                guard blocks.count > 1 else { return nil }
                return (
                    album,
                    blocks.map { (artist: $0.key, tracks: $0.value) }
                        .sorted { $0.tracks.count > $1.tracks.count }
                )
            }
            .sorted { $0.blocks.count > $1.blocks.count }
    }
}
