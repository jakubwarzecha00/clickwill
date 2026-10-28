import Foundation

/// One size variant of an artwork image - one slice of an `.ithmb` file.
public struct ArtworkVariant: Sendable, Hashable {
    /// Format identifier, e.g. 1060. Matches the file name `F1060_1.ithmb`.
    public let correlationID: UInt32
    /// File name as stored in the database, e.g. `:F1060_1.ithmb` - relative to the `Artwork` folder.
    public let fileName: String
    public let byteOffset: UInt32
    public let byteCount: UInt32
    public let width: UInt16
    public let height: UInt16

    public init(correlationID: UInt32, fileName: String, byteOffset: UInt32, byteCount: UInt32, width: UInt16, height: UInt16) {
        self.correlationID = correlationID
        self.fileName = fileName
        self.byteOffset = byteOffset
        self.byteCount = byteCount
        self.width = width
        self.height = height
    }

    /// File name without the leading colon.
    public var plainFileName: String {
        var name = fileName
        while name.hasPrefix(":") { name.removeFirst() }
        return name
    }

    /// Number of pixels in a row as stored in the file.
    ///
    /// A slot can be wider than the image itself: format 1061 reserves 6160 bytes
    /// for a 55x55 image, which gives a row stride of 56 pixels, not 55.
    public var pixelStride: Int {
        guard height > 0 else { return Int(width) }
        return Int(byteCount) / (2 * Int(height))
    }

    /// URL of the `.ithmb` file. The name comes from `ArtworkDB`, so it is checked:
    /// only `F<format>_<n>.ithmb` in the Artwork folder, no `..` and no links
    /// pointing outside (security audit 0.1.3).
    public func url(in paths: IPodPaths) throws -> URL {
        guard let url = paths.artworkFile(plainFileName) else { throw ITDBError.unsafePath(plainFileName) }
        return url
    }

    /// A slice with sensible dimensions. The largest known image is 320x320
    /// (204,800 B); the limit leaves headroom without reading megabytes from the database.
    public var hasSaneBounds: Bool {
        hasSaneSlotSize && width > 0 && height > 0 && width <= 2048 && height <= 2048
    }

    /// The slice size alone - for raw byte comparisons where dimensions do not matter.
    public var hasSaneSlotSize: Bool { byteCount > 0 && byteCount <= 4_194_304 }
}

/// Artwork of one track - an `mhii` record.
public struct ArtworkImage: Sendable, Identifiable {
    public let id: UInt32
    /// Points to the track's `persistentID` in `iTunesDB`.
    public let trackPersistentID: UInt64
    public let variants: [ArtworkVariant]
    public let rawHeader: [UInt8]

    /// The largest available variant - for previews in the interface.
    public var largest: ArtworkVariant? {
        variants.max { $0.byteCount < $1.byteCount }
    }

    public func variant(correlationID: UInt32) -> ArtworkVariant? {
        variants.first { $0.correlationID == correlationID }
    }
}

/// Format description from the file section - an `mhif` record.
public struct ArtworkFormat: Sendable, Hashable {
    public let correlationID: UInt32
    /// How many bytes one image takes in the `.ithmb` file.
    public let slotSize: UInt32
}

/// Contents of `ArtworkDB`.
public struct ArtworkLibrary: Sendable {
    public let images: [ArtworkImage]
    public let formats: [ArtworkFormat]
    public let rawHeader: [UInt8]
    public let sourceByteCount: Int

    public func image(forTrackPersistentID id: UInt64) -> ArtworkImage? {
        images.first { $0.trackPersistentID == id }
    }

    /// Map of `track persistentID -> artwork`, for fast linking with the library.
    public func indexedByTrack() -> [UInt64: ArtworkImage] {
        Dictionary(images.map { ($0.trackPersistentID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Reads `ArtworkDB`.
///
/// Note: the layout differs from `iTunesDB` in two places, and mixing them up misaligns the file.
/// First, an `mhod` of type 2 is a **container** holding a nested `mhni` record,
/// not text. Second, strings have different offsets: the length sits right after the header,
/// the encoding four bytes later, and the characters start twelve bytes after the header
/// instead of sixteen.
public enum ArtworkDBParser {

    public static func parse(_ data: Data) throws -> ArtworkLibrary {
        let reader = ByteReader(data)
        guard try reader.signature(at: 0) == "mhfd" else {
            throw ITDBError.unexpectedSignature(expected: "mhfd", found: try reader.signature(at: 0), offset: 0)
        }
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: 0))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: 0))
        guard totalLength == reader.count else {
            throw ITDBError.lengthMismatch(declared: totalLength, actual: reader.count)
        }

        let sectionCount = Int(try reader.value(MhfdLayout.sectionCount, inRecordAt: 0))
        var images: [ArtworkImage] = []
        var formats: [ArtworkFormat] = []
        var offset = headerLength

        for _ in 0..<sectionCount {
            let sectionTotal = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
            let listOffset = offset + Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
            let listSignature = try reader.signature(at: listOffset)
            let listHeaderLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: listOffset))
            let childCount = Int(try reader.value(RecordLayout.listChildCount, inRecordAt: listOffset))
            var cursor = listOffset + listHeaderLength

            switch listSignature {
            case "mhli":
                images.reserveCapacity(childCount)
                for _ in 0..<childCount {
                    let (image, next) = try parseImage(reader, at: cursor)
                    images.append(image)
                    cursor = next
                }
            case "mhlf":
                formats.reserveCapacity(childCount)
                for _ in 0..<childCount {
                    formats.append(
                        ArtworkFormat(
                            correlationID: try reader.value(MhifLayout.formatID, inRecordAt: cursor),
                            slotSize: try reader.value(MhifLayout.slotSize, inRecordAt: cursor)
                        )
                    )
                    cursor += Int(try reader.value(RecordLayout.totalLength, inRecordAt: cursor))
                }
            default:
                break   // `mhla` holds photo albums - not relevant to music
            }
            offset += sectionTotal
        }

        return ArtworkLibrary(
            images: images,
            formats: formats,
            rawHeader: try reader.slice(0..<headerLength),
            sourceByteCount: reader.count
        )
    }

    private static func parseImage(_ reader: ByteReader, at offset: Int) throws -> (ArtworkImage, Int) {
        guard try reader.signature(at: offset) == "mhii" else {
            throw ITDBError.unexpectedSignature(
                expected: "mhii", found: try reader.signature(at: offset), offset: offset
            )
        }
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let totalLength = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
        let childCount = Int(try reader.value(MhiiLayout.childCount, inRecordAt: offset))

        var variants: [ArtworkVariant] = []
        var cursor = offset + headerLength
        for _ in 0..<childCount {
            let mhodTotal = Int(try reader.value(RecordLayout.totalLength, inRecordAt: cursor))
            let mhodType = try reader.value(ArtworkMhodLayout.type, inRecordAt: cursor)
            if mhodType == ArtworkMhodLayout.variantContainer {
                variants.append(try parseVariant(reader, at: cursor + ArtworkMhodLayout.headerLength))
            }
            cursor += mhodTotal
        }

        let image = ArtworkImage(
            id: try reader.value(MhiiLayout.imageID, inRecordAt: offset),
            trackPersistentID: try reader.value(MhiiLayout.ownerPersistentID, inRecordAt: offset),
            variants: variants,
            rawHeader: try reader.slice(offset..<(offset + headerLength))
        )
        return (image, offset + totalLength)
    }

    /// `mhni` - where in the `.ithmb` file the image lies and how large it is.
    private static func parseVariant(_ reader: ByteReader, at offset: Int) throws -> ArtworkVariant {
        guard try reader.signature(at: offset) == "mhni" else {
            throw ITDBError.unexpectedSignature(
                expected: "mhni", found: try reader.signature(at: offset), offset: offset
            )
        }
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let nameOffset = offset + headerLength

        return ArtworkVariant(
            correlationID: try reader.value(MhniLayout.formatID, inRecordAt: offset),
            fileName: try parseFileName(reader, at: nameOffset),
            byteOffset: try reader.value(MhniLayout.byteOffset, inRecordAt: offset),
            byteCount: try reader.value(MhniLayout.byteCount, inRecordAt: offset),
            width: try reader.value(MhniLayout.width, inRecordAt: offset),
            height: try reader.value(MhniLayout.height, inRecordAt: offset)
        )
    }

    /// A string in `ArtworkDB` (`ArtworkMhodLayout.Text`).
    private static func parseFileName(_ reader: ByteReader, at offset: Int) throws -> String {
        guard try reader.signature(at: offset) == "mhod" else { return "" }
        let headerLength = Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
        let body = offset + headerLength
        let byteCount = Int(try reader.value(ArtworkMhodLayout.Text.byteCount, inRecordAt: body))
        guard byteCount > 0 else { return "" }
        return try reader.utf16String(at: body + ArtworkMhodLayout.Text.start, byteCount: byteCount)
    }
}
