import Foundation

/// Type of an `mhod` record - the container for all text and auxiliary data in the database.
///
/// Deliberately a struct, not an `enum`: the database contains types we do not know, and
/// they must survive reading and writing unchanged. An unknown type is simply another value,
/// not a parse error.
///
/// Meanings marked as **confirmed** were established on a real database:
/// for each candidate we checked whether its value matches the displayed field
/// after stripping the article. The rest comes from the format description and does not
/// occur in that database, so it was not verified.
public struct MhodType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    // Track text fields - confirmed
    public static let title = MhodType(rawValue: 1)
    public static let location = MhodType(rawValue: 2)
    public static let album = MhodType(rawValue: 3)
    public static let artist = MhodType(rawValue: 4)
    public static let genre = MhodType(rawValue: 5)
    public static let fileType = MhodType(rawValue: 6)
    public static let comment = MhodType(rawValue: 8)
    public static let composer = MhodType(rawValue: 12)
    public static let albumArtist = MhodType(rawValue: 22)

    // Sort fields - confirmed on 1619 tracks.
    // These, not the displayed fields, decide the order in the iPod menu.
    public static let sortArtist = MhodType(rawValue: 23)
    public static let sortTitle = MhodType(rawValue: 27)
    public static let sortAlbum = MhodType(rawValue: 28)
    public static let sortAlbumArtist = MhodType(rawValue: 29)

    // From the format description, absent from the test database
    public static let eqSetting = MhodType(rawValue: 7)
    public static let category = MhodType(rawValue: 9)
    public static let grouping = MhodType(rawValue: 13)
    public static let description = MhodType(rawValue: 14)
    public static let podcastURL = MhodType(rawValue: 15)
    public static let podcastRSS = MhodType(rawValue: 16)
    public static let chapterData = MhodType(rawValue: 17)
    public static let subtitle = MhodType(rawValue: 18)
    public static let tvShow = MhodType(rawValue: 19)
    public static let tvEpisode = MhodType(rawValue: 20)
    public static let tvNetwork = MhodType(rawValue: 21)
    public static let keywords = MhodType(rawValue: 24)
    public static let sortComposer = MhodType(rawValue: 30)
    public static let sortTVShow = MhodType(rawValue: 31)

    // Binary data - stored without interpretation
    public static let smartPlaylistData = MhodType(rawValue: 50)
    public static let smartPlaylistRules = MhodType(rawValue: 51)
    public static let libraryPlaylistIndex = MhodType(rawValue: 52)
    public static let libraryPlaylistJumpTable = MhodType(rawValue: 53)
    public static let playlistEntryData = MhodType(rawValue: 100)
    public static let playlistPreference = MhodType(rawValue: 102)

    // Album fields in the `mhla` section - confirmed
    public static let albumTitle = MhodType(rawValue: 200)
    public static let albumArtistName = MhodType(rawValue: 201)
    public static let albumSortArtist = MhodType(rawValue: 202)

    /// Whether the content is UTF-16 text or opaque bytes.
    ///
    /// Established empirically: types 50-53 plus 100 and 102 are binary data,
    /// the rest in that database decodes as text.
    public var carriesText: Bool {
        switch rawValue {
        case 50...53, 100, 102: return false
        default: return true
        }
    }

    public var label: String {
        switch self {
        case .title: return "title"
        case .location: return "path"
        case .album: return "album"
        case .artist: return "artist"
        case .genre: return "genre"
        case .fileType: return "file type"
        case .comment: return "comment"
        case .composer: return "composer"
        case .albumArtist: return "album artist"
        case .sortArtist: return "sort: artist"
        case .sortTitle: return "sort: title"
        case .sortAlbum: return "sort: album"
        case .sortAlbumArtist: return "sort: album artist"
        case .albumTitle: return "album (album list)"
        case .albumArtistName: return "artist (album list)"
        case .albumSortArtist: return "sort: artist (album list)"
        default: return "type \(rawValue)"
        }
    }
}
