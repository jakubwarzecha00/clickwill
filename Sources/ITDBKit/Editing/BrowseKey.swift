import Foundation

/// The key by which the device orders one browse criterion.
///
/// We do not try to reproduce iTunes collation character for character - that would be guessing.
/// The key serves only to **find a place among entries already in order**:
/// we walk the existing table and insert the new track before the first one that
/// is greater than it. The existing order comes from iTunes and stays
/// untouched, so even a difference in comparison rules can shift the new
/// track only by a few positions among neighbors with similar names.
public struct BrowseKey: Comparable, Sendable {

    public struct Segment: Comparable, Sendable {
        /// 0 - starts with a letter, 1 - with a digit or another script, 2 - empty.
        /// This order is visible in the jump bars the device writes.
        let rank: Int
        let text: String

        public static func < (lhs: Segment, rhs: Segment) -> Bool {
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.text < rhs.text
        }
    }

    public let segments: [Segment]

    public static func < (lhs: BrowseKey, rhs: BrowseKey) -> Bool {
        for (left, right) in zip(lhs.segments, rhs.segments) where left != right {
            return left < right
        }
        return lhs.segments.count < rhs.segments.count
    }

    static func text(_ value: String?) -> Segment {
        let folded = (value ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = folded.first(where: { $0.isLetter || $0.isNumber }) else {
            return Segment(rank: 2, text: "")
        }
        let rank = first.isASCII && first.isLetter ? 0 : 1
        return Segment(rank: rank, text: folded.lowercased())
    }

    /// A number as fixed-width text - so that 2 comes before 10.
    static func number(_ value: UInt32) -> Segment {
        Segment(rank: 0, text: String(format: "%06u", value))
    }
}

extension ITLibrary {

    /// Criteria whose ordering we can name. For the others we check whether their
    /// table is a copy of one of these - and if not, we do not guess.
    static let knownCriteria: [BrowseIndex.Criterion] = [.title, .album, .artist, .genre, .composer]

    /// A track's key for a given criterion. Sort fields take precedence over
    /// displayed ones - they decide the place in the iPod menu.
    public static func browseKey(_ criterion: BrowseIndex.Criterion, for track: ITTrack) -> BrowseKey {
        let album = BrowseKey.text(track.sortAlbum ?? track.album)
        let disc = BrowseKey.number(track.discNumber)
        let number = BrowseKey.number(track.trackNumber)
        let title = BrowseKey.text(track.sortTitle ?? track.title)
        let artist = BrowseKey.text(track.sortAlbumArtist ?? track.sortArtist ?? track.effectiveAlbumArtist)

        switch criterion {
        case .title:
            return BrowseKey(segments: [title, artist, album])
        case .album:
            return BrowseKey(segments: [album, artist, disc, number, title])
        case .artist:
            return BrowseKey(segments: [artist, album, disc, number, title])
        case .genre:
            return BrowseKey(segments: [BrowseKey.text(track.genre), artist, album, disc, number])
        case .composer:
            return BrowseKey(segments: [BrowseKey.text(track.composer), album, disc, number])
        default:
            return BrowseKey(segments: [title])
        }
    }

    /// The character under which a new track goes into the jump bar of a given criterion.
    static func letterCode(_ criterion: BrowseIndex.Criterion, for track: ITTrack) -> UInt32 {
        let value: String?
        switch criterion {
        case .album: value = track.sortAlbum ?? track.album
        case .artist: value = track.sortAlbumArtist ?? track.sortArtist ?? track.effectiveAlbumArtist
        case .genre: value = track.genre
        case .composer: value = track.composer
        default: value = track.sortTitle ?? track.title
        }
        return letterCode(for: value ?? "")
    }
}
