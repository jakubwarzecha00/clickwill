import Foundation

/// The Albums menu as the iPod classic shows it.
///
/// The iPod lays out this menu itself, on the fly - not from the album table in the database. The table
/// can hold an album in two places (Metallica: 1 track under B, 11 under N),
/// and the menu still shows it once, in its place in the alphabet. The rule was
/// checked on a classic 7G, with five readings from the device:
/// - the name from the album's sort field, ignoring case and accents, without
///   characters before the first letter or digit ("...But Seriously" under B)
///   and without a leading "The " ("The Bends" under B);
/// - Latin letters first, then other scripts, then digits, and at the end
///   an album without a name ("Yeezus", a Japanese album, "4X4", "808s", "").
///
/// A menu item is a Cover Flow card - the same album from tracks scattered
/// across the table, which the iPod shows as one.
public enum AlbumsMenu {

    public struct Key: Comparable, Sendable {
        /// 0 - a Latin letter, 1 - another script, 2 - a digit, 3 - no name.
        let rank: Int
        let name: String

        public static func < (lhs: Key, rhs: Key) -> Bool {
            (lhs.rank, lhs.name) < (rhs.rank, rhs.name)
        }
    }

    public static func key(_ album: AlbumCard) -> Key {
        var name = (album.albumSortName ?? album.title)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        name = String(name.drop { !($0.isLetter || $0.isNumber) })
        if name.hasPrefix("the ") { name.removeFirst(4) }
        guard let first = name.first else { return Key(rank: 3, name: "") }
        let rank = first.isASCII && first.isLetter ? 0 : first.isASCII && first.isNumber ? 2 : 1
        return Key(rank: rank, name: name)
    }

    /// Albums in menu order. The same name - by artist, then as they came.
    public static func order(_ albums: [AlbumCard]) -> [AlbumCard] {
        albums.enumerated()
            .map { (offset: $0.offset, card: $0.element, key: key($0.element)) }
            .sorted { lhs, rhs in
                if lhs.key != rhs.key { return lhs.key < rhs.key }
                if lhs.card.artistSortKey != rhs.card.artistSortKey { return lhs.card.artistSortKey < rhs.card.artistSortKey }
                return lhs.offset < rhs.offset
            }
            .map(\.card)
    }

    /// The letter the album stands under in the menu: an uppercase Latin letter, digits
    /// and other scripts under `#`, an album without a name without a letter.
    public static func letter(of album: AlbumCard) -> String {
        let key = key(album)
        switch key.rank {
        case 0: return key.name.prefix(1).uppercased()
        case 3: return ""
        default: return "#"
        }
    }
}
