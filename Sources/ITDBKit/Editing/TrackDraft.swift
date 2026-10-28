import Foundation

/// A track about to go into the library: everything we know from the file and its tags,
/// plus the place where the file already lies on the device.
///
/// The file is copied **before** the database is touched, so a draft always carries a ready
/// path. The reverse order would, if interrupted, leave an entry pointing
/// into the void, which the iPod shows as a track that refuses to play.
public struct TrackDraft: Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var composer: String?
    public var comment: String?
    public var year: UInt32
    public var trackNumber: UInt32
    public var totalTracks: UInt32
    public var discNumber: UInt32
    public var totalDiscs: UInt32
    public var isCompilation: Bool

    public var durationMilliseconds: UInt32
    public var sizeBytes: UInt32
    public var bitRate: UInt32
    public var sampleRate: UInt32
    public var kind: TrackFileKind
    /// Path relative to the volume root, with slashes.
    public var relativePath: String

    public init(
        id: UUID = UUID(), title: String, artist: String? = nil, albumArtist: String? = nil,
        album: String? = nil, genre: String? = nil, composer: String? = nil, comment: String? = nil,
        year: UInt32 = 0, trackNumber: UInt32 = 0, totalTracks: UInt32 = 0,
        discNumber: UInt32 = 0, totalDiscs: UInt32 = 0, isCompilation: Bool = false,
        durationMilliseconds: UInt32 = 0, sizeBytes: UInt32 = 0, bitRate: UInt32 = 0,
        sampleRate: UInt32 = 44_100, kind: TrackFileKind, relativePath: String
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.composer = composer
        self.comment = comment
        self.year = year
        self.trackNumber = trackNumber
        self.totalTracks = totalTracks
        self.discNumber = discNumber
        self.totalDiscs = totalDiscs
        self.isCompilation = isCompilation
        self.durationMilliseconds = durationMilliseconds
        self.sizeBytes = sizeBytes
        self.bitRate = bitRate
        self.sampleRate = sampleRate
        self.kind = kind
        self.relativePath = relativePath
    }

    /// The artist used for grouping - the same as in `ITTrack`.
    public var effectiveAlbumArtist: String { albumArtist ?? artist ?? "" }

    public var albumKey: AlbumKey { AlbumKey(album: album ?? "", albumArtist: effectiveAlbumArtist) }
}

public enum TrackInsertionError: Error, CustomStringConvertible {
    case noTemplate(TrackFileKind)
    case noMasterPlaylist
    case emptyTitle
    case pathAlreadyUsed(String)
    case jumpTableMismatch(criterion: UInt32, covered: Int, expected: Int)
    case permutationBroken(criterion: UInt32)
    case noFreePersistentID

    public var description: String {
        switch self {
        case .noTemplate(let kind):
            return "Clickwill can't add the first \(kind.fileTypeDescription) song to this iPod yet. "
                + "Add one song in that format with Music, then try again."
        case .noMasterPlaylist:
            return "This iPod's library is missing its main song list. Restore the iPod with Finder, then try again."
        case .emptyTitle:
            return "A song needs a title."
        case .pathAlreadyUsed(let path):
            return "Another song already uses the file \(path). Nothing was changed."
        case .jumpTableMismatch(let criterion, let covered, let expected):
            return "Clickwill stopped adding songs because one of the iPod's menus didn't check out (\(criterion): \(covered) of \(expected)). Nothing was changed. Choose Send Feedback so I can look into it."
        case .permutationBroken(let criterion):
            return "Clickwill stopped adding songs because one of the iPod's menus didn't check out (\(criterion)). Nothing was changed. Choose Send Feedback so I can look into it."
        case .noFreePersistentID:
            return "Clickwill couldn't find a free ID for the new song. Try again."
        }
    }
}
