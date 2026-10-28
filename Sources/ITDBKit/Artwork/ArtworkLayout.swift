import Foundation

// Header layouts of `ArtworkDB` records - the only place with their offsets.
// The start of every record (signature, header length, total length or number
// of children in lists) is the same as in iTunesDB - `RecordLayout`.

/// `mhfd` - file header (0x84 B).
public enum MhfdLayout {
    public static let headerLength = 0x84
    /// 6 as written by Music, constant in all backups.
    public static let version = HeaderField<UInt32>(0x10)
    /// Number of sections: 3.
    public static let sectionCount = HeaderField<UInt32>(0x14)
    /// Next free image identifier.
    public static let nextImageID = HeaderField<UInt32>(0x1C)
    /// 16 B file identifier; Music may write a new one on save.
    public static let identity = 0x20..<0x30
    /// 1, constant.
    public static let unknown30 = HeaderField<UInt32>(0x30)
    /// Second file identifier, 8 B.
    public static let secondIdentity = 0x3C..<0x44
}

/// `mhsd` in `ArtworkDB`: type 1 = images (`mhli`), 2 = albums (`mhla`),
/// 3 = formats (`mhlf`).
public enum ArtworkSectionLayout {
    public static let headerLength = 0x60
    public static let type = HeaderField<UInt32>(0x0C)
    public static let images: UInt32 = 1
    public static let albums: UInt32 = 2
    public static let formats: UInt32 = 3
    /// Header of the `mhli`, `mhla` and `mhlf` lists.
    public static let listHeaderLength = 0x5C
}

/// `mhii` - image record (0x98 B).
public enum MhiiLayout {
    public static let headerLength = 0x98
    public static let childCount = HeaderField<UInt32>(0x0C)
    /// Image identifier - `mhit` 0x160 points to it.
    public static let imageID = HeaderField<UInt32>(0x10)
    /// `persistentID` of the owner track.
    public static let ownerPersistentID = HeaderField<UInt64>(0x14)
    /// Source size; rule: = `mhit` 0x80 + 0x7C.
    public static let sourceByteCount = HeaderField<UInt32>(0x30)
    /// How many tracks it applies to - does not control artwork visibility.
    public static let trackCount = HeaderField<UInt32>(0x38)
    /// 1 in all examined records.
    public static let unknown3C = HeaderField<UInt32>(0x3C)
    /// Double NaN in all examined records.
    public static let unknown48 = HeaderField<UInt64>(0x48)
    public static let unknown50 = HeaderField<UInt64>(0x50)
}

/// `mhod` in `ArtworkDB` - different from iTunesDB: type 2 is a **container** for
/// `mhni`, and text (type 3) starts 12 bytes after the header, not 16.
public enum ArtworkMhodLayout {
    public static let headerLength = 0x18
    public static let type = HeaderField<UInt32>(0x0C)
    /// Container for an image variant (`mhni`).
    public static let variantContainer: UInt32 = 2
    /// Name of the `.ithmb` file.
    public static let fileName: UInt32 = 3

    /// Text content, offsets from the start of the content.
    public enum Text {
        public static let byteCount = HeaderField<UInt32>(0x00)
        /// 2 = UTF-16LE.
        public static let encoding = HeaderField<UInt32>(0x04)
        public static let start = 0x0C
    }
}

/// `mhni` - an image variant in one format (0x4C B).
public enum MhniLayout {
    public static let headerLength = 0x4C
    public static let childCount = HeaderField<UInt32>(0x0C)
    /// Format identifier (1055, 1060, 1061; nano 2G: 1027, 1031).
    public static let formatID = HeaderField<UInt32>(0x10)
    /// Offset in the `.ithmb` file.
    public static let byteOffset = HeaderField<UInt32>(0x14)
    public static let byteCount = HeaderField<UInt32>(0x18)
    /// Height comes before width.
    public static let height = HeaderField<UInt16>(0x20)
    public static let width = HeaderField<UInt16>(0x22)
    /// The size once more (= `byteCount`).
    public static let byteCountAgain = HeaderField<UInt32>(0x28)
}

/// `mhif` - image format (0x7C B).
public enum MhifLayout {
    public static let headerLength = 0x7C
    public static let formatID = HeaderField<UInt32>(0x10)
    public static let slotSize = HeaderField<UInt32>(0x14)
}
