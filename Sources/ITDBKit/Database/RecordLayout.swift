import Foundation

// Header layouts of iTunesDB records - the only place with their offsets.
// A measurement correction lands here once, and the parser, the writer and the
// repairs take it from here.

/// The start of every record: signature (0x00), header length, total
/// length including children.
public enum RecordLayout {
    public static let headerLength = HeaderField<UInt32>(0x04)
    public static let totalLength = HeaderField<UInt32>(0x08)
    /// In the `mhlt`, `mhlp` and `mhla` lists, 0x08 holds the number of children, not a length.
    public static let listChildCount = HeaderField<UInt32>(0x08)
}

/// `mhbd` - the header of the whole database.
public enum MhbdLayout {
    public static let version = HeaderField<UInt32>(0x10)
    public static let sectionCount = HeaderField<UInt32>(0x14)
    public static let databaseID = HeaderField<UInt64>(0x18)
    /// Signing scheme number (`Hash58.Layout.hashingSchemeOffset`).
    public static let hashingScheme = HeaderField<UInt16>(Hash58.Layout.hashingSchemeOffset)
}

/// `mhsd` - a section (tracks, playlists, albums or a type we do not know).
public enum MhsdLayout {
    public static let type = HeaderField<UInt32>(0x0C)
}

/// `mhyp` - a playlist.
public enum MhypLayout {
    public static let mhodCount = HeaderField<UInt32>(0x0C)
    public static let entryCount = HeaderField<UInt32>(0x10)
    /// 1 = the master playlist (the list of all tracks and the browse tables).
    public static let isMaster = HeaderField<UInt8>(0x14)
    public static let persistentID = HeaderField<UInt64>(0x18)
}

/// `mhip` - a playlist item.
public enum MhipLayout {
    public static let mhodCount = HeaderField<UInt32>(0x0C)
    public static let order = HeaderField<UInt32>(0x14)
    /// The track's `uniqueID` (`mhit` 0x10).
    public static let trackID = HeaderField<UInt32>(0x18)
}

/// `mhia` - an album record.
public enum MhiaLayout {
    public static let mhodCount = HeaderField<UInt32>(0x0C)
    /// The index that `mhit` 0x120 points to. Format descriptions give 4 bytes; we read
    /// and write the lower 2, the upper ones stay from the original header.
    public static let index = HeaderField<UInt16>(0x10)
    /// The album's `persistentID` - upper word `0x00000002` or `0x00000102`.
    public static let persistentID = HeaderField<UInt64>(0x18)
    /// `persistentID` of the track whose image is the album artwork - that is how
    /// `linkingAlbumArtwork` uses it. The field does not decide how artwork is
    /// linked (Cover Flow links through the `mhii` owner).
    public static let artworkOwner = HeaderField<UInt64>(0x20)
}

/// `mhod` - a text field or auxiliary data.
public enum MhodLayout {
    public static let type = HeaderField<UInt32>(0x0C)

    /// Text content after the header (established on a real database): position,
    /// text length in bytes, encoding (1 = UTF-16LE), an unused field,
    /// and from 0x10 the text itself. Offsets counted from the start of the content.
    public enum Text {
        public static let position = HeaderField<UInt32>(0x00)
        public static let byteCount = HeaderField<UInt32>(0x04)
        public static let encoding = HeaderField<UInt32>(0x08)
        public static let start = 0x10
    }

    /// Content of a browse table (type 52) and an alphabetical jump bar
    /// (type 53): criterion and entry count at the start of the preamble, entries after it.
    public enum BrowseBody {
        public static let criterion = HeaderField<UInt32>(0x00)
        public static let entryCount = HeaderField<UInt32>(0x04)
    }
}

/// `mhit` - a track (624 B header).
public enum MhitLayout {
    public static let mhodCount = HeaderField<UInt32>(0x0C)
    /// Browse tables hold it - never change it for an existing track.
    public static let uniqueID = HeaderField<UInt32>(0x10)
    /// 1 = visible.
    public static let visible = HeaderField<UInt32>(0x14)
    /// Four-character container code (`MP3 `, `M4A `), reversed in the file.
    public static let fileTypeCode = HeaderField<UInt32>(0x18)
    public static let type1 = HeaderField<UInt8>(0x1C)
    /// 1 only for MP3.
    public static let mpegFlag = HeaderField<UInt8>(0x1D)
    /// Compilation flag: the album goes into the "Compilations" group at the end of Cover Flow.
    public static let compilation = HeaderField<UInt8>(0x1E)
    public static let rating = HeaderField<UInt8>(0x1F)
    /// Modification date (Mac time).
    public static let dateModified = HeaderField<UInt32>(0x20)
    public static let sizeBytes = HeaderField<UInt32>(0x24)
    public static let durationMilliseconds = HeaderField<UInt32>(0x28)
    public static let trackNumber = HeaderField<UInt32>(0x2C)
    public static let totalTracks = HeaderField<UInt32>(0x30)
    public static let year = HeaderField<UInt32>(0x34)
    /// kb/s.
    public static let bitRate = HeaderField<UInt32>(0x38)
    /// Sample rate in the upper 16 bits; the lower ones are preserved.
    public static let sampleRate = HeaderField<UInt32>(0x3C)
    public static let playCount = HeaderField<UInt32>(0x50)
    /// Zeroed on insertion; meaning unknown.
    public static let unknown54 = HeaderField<UInt32>(0x54)
    /// Last played (Mac time).
    public static let lastPlayed = HeaderField<UInt32>(0x58)
    public static let discNumber = HeaderField<UInt32>(0x5C)
    public static let totalDiscs = HeaderField<UInt32>(0x60)
    /// Date added (Mac time).
    public static let dateAdded = HeaderField<UInt32>(0x68)
    /// `ArtworkDB` links the image owner by it (`mhii` 0x14).
    public static let persistentID = HeaderField<UInt64>(0x70)
    /// Artwork count - a **two-byte** field; writing four bytes wiped 0x7E.
    public static let artworkCount = HeaderField<UInt16>(0x7C)
    /// Artwork marker, always `0xFFFF` from iTunes, even when 0x7C = 0.
    public static let artworkMarker = HeaderField<UInt16>(0x7E)
    /// Artwork source size; rule: `mhii` 0x30 = 0x80 + 0x7C.
    public static let artworkSourceSize = HeaderField<UInt32>(0x80)
    /// Sample rate as a `Float` - the second place iTunes keeps it.
    public static let sampleRateFloat = HeaderField<UInt32>(0x88)
    /// Zero even in working albums; meaning unknown, zeroed on insertion.
    public static let unknown98 = HeaderField<UInt32>(0x98)
    public static let unknown9C = HeaderField<UInt32>(0x9C)
    public static let unknownA0 = HeaderField<UInt32>(0xA0)
    /// 1 = the track points to an image (0x160), 2 = it does not.
    public static let artworkPresence = HeaderField<UInt8>(0xA4)
    /// Second copy of the `persistentID` (a copy of 0x70).
    public static let secondaryPersistentID = HeaderField<UInt64>(0xA8)
    /// Album record index (`mhia` 0x10).
    public static let albumRecordIndex = HeaderField<UInt32>(0x120)
    /// Second record of the file size.
    public static let sizeBytesSecondary = HeaderField<UInt32>(0x12C)
    /// `0x02000000` for Apple Lossless.
    public static let losslessFlag = HeaderField<UInt32>(0x148)
    /// Image record identifier (`mhii` 0x10) - the iPod follows it to the artwork
    /// during playback.
    public static let artworkIdentifier = HeaderField<UInt32>(0x160)
    /// Set to `uniqueID + 1`, as iTunes does; meaning unknown.
    public static let uniqueIDPlusOne = HeaderField<UInt32>(0x1F4)
}
