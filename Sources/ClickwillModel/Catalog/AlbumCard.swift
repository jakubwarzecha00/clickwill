import Foundation
import ITDBKit

/// The identity of an album card that survives editing.
///
/// It comes from the card's tracks, not from the title or the position: changing the title,
/// moving the album and reordering tracks do not change it. It changes
/// only when the anchor track (the smallest `persistentID`) disappears from the card -
/// then `AlbumCatalog.current(_:)` finds the current card by the remaining
/// tracks.
public enum AlbumID: Hashable, Sendable {
    /// An album, i.e. a block of the album table, or a Cover Flow card covering
    /// such a whole block.
    case album(UInt64)
    /// A Cover Flow card assembled from parts of blocks (tracks without an album, different
    /// artists in one block). It has no single block, so it cannot be
    /// edited like an album.
    case coverFlowPart(UInt64)
    /// A new album from the add queue - no tracks on the iPod yet.
    case pending(AlbumKey)

    /// The anchor: the smallest `persistentID` - it does not depend on the track order.
    static func anchor(of persistentIDs: [UInt64]) -> UInt64 { persistentIDs.min() ?? 0 }

    /// The album (a whole block of the album table) from these tracks - the same
    /// identifier its card gets in `AlbumCatalog`.
    public init(albumOf tracks: [ITTrack]) {
        self = .album(Self.anchor(of: tracks.map(\.persistentID)))
    }
}

/// An album as the album list and Cover Flow show it.
public struct AlbumCard: Identifiable, Hashable, Sendable {
    public let id: AlbumID
    /// Positions of the `mhit` records in display order. Current only for
    /// a card from the current catalog - after an edit, take the card anew.
    public let trackIndices: [Int]
    /// The card's tracks (`persistentID`) in display order - the card
    /// finds itself by them after an edit.
    public let trackIDs: [UInt64]
    public let title: String
    public let artist: String
    public let year: UInt32?
    public let genre: String?
    public let trackCount: Int
    public let duration: TimeInterval
    /// The persistent identifier of the track we take the artwork from.
    public let artworkTrackID: UInt64?
    /// Whether the album has artwork. A card without artwork still has an `artworkTrackID` -
    /// a hook for previewing newly chosen artwork.
    public var hasArtwork = true
    /// The album's sort field (e.g. "Bends" for "The Bends") - the iPod orders
    /// the Albums menu by it (`AlbumsMenu`). `nil` - it sorts by the title.
    public var albumSortName: String?
    public let missingFiles: Int
    public let isCompilation: Bool
    /// The key by which Cover Flow places the artist group: the album artist's sort
    /// field, then the artist's, then the name without a leading "The ".
    public let artistSortKey: String

    /// A new album from the add queue: not on the iPod yet, shown
    /// in Cover Flow where it will stand after the write. It has no `mhit` records,
    /// so it must not be edited like a regular card.
    public var isPending: Bool {
        if case .pending = id { return true }
        return false
    }

    public var displayTitle: String { title.isEmpty ? "Unknown Album" : title }
    public var displayArtist: String { artist.isEmpty ? "Unknown Artist" : artist }
}

/// A track in the album view.
public struct TrackRow: Identifiable, Hashable, Sendable {
    public let id: UInt32
    public let persistentID: UInt64
    public let title: String
    public let artist: String
    public let number: UInt32
    public let duration: TimeInterval
    public let playCount: UInt32
    public let fileMissing: Bool
    /// The format compatibility verdict; `nil` until the file has been examined.
    public var formatVerdict: AudioCompatibility.Verdict?
    /// Format description for the interface, e.g. "ALAC 24-bit 48 kHz".
    public var formatLabel: String?

    public var displayTitle: String { title.isEmpty ? "Untitled" : title }
    /// The iPod will not play this - it will skip to the next track.
    public var unplayable: Bool { formatVerdict.map { !$0.isSupported } ?? false }
}
