import Foundation

/// Builds `ArtworkDB` from scratch - for an iPod that has no artwork at all yet.
///
/// Finder does not create this file on the nano 2G (measured: after syncing
/// 13 tracks with artwork there is no `Artwork` folder, and the nano shows
/// no artwork). So there is no Apple template for this model. The record
/// layout comes from the `ArtworkDB` that Music writes on the Classic (41 backups,
/// 144 images - values described as constant are identical in all of them), and
/// the formats from the description the device firmware provides (`DeviceDescription.albumArt`).
///
/// Layout as written by Music - offsets and constant values are in `ArtworkLayout.swift`.
/// The two file identifiers (`MhfdLayout.identity`, `secondIdentity`) are randomized
/// once, on creation, and left alone in an existing file: the second is constant,
/// and Music may change the first on write. Sections have types 1, 2 and 3:
/// images (`mhli`), photo albums (`mhla`, empty) and formats (`mhlf`).
///
/// We deliberately skip Music's fourth `mhii` child, an `mhod` of type 6
/// with an `mhaf` record (all zeros). We do not know what that record means, and
/// the nano 2G firmware dates from 2007 - older than the record itself.
public enum ArtworkDBBuilder {

    /// An artwork format in the form in which it goes into `ArtworkDB`.
    public struct Format: Sendable, Hashable {
        public let formatID: UInt32
        public let width: Int
        public let height: Int

        public init(formatID: UInt32, width: Int, height: Int) {
            self.formatID = formatID
            self.width = width
            self.height = height
        }

        /// From the device description. `nil` for an encoding we cannot write.
        public init?(_ format: DeviceDescription.ImageFormat) {
            guard format.isLittleEndianRGB565, format.width > 0, format.height > 0 else { return nil }
            self.init(formatID: format.formatID, width: format.width, height: format.height)
        }

        /// Row aligned to 4 bytes (`AlignRowBytes` in the device description).
        /// On the Classic, 1061 is 55 px wide with a 56 px stride and a 6160 B slot -
        /// 4-byte alignment explains it. For 42 and 100 px the row is a multiple of 4 anyway.
        public var rowBytes: Int { (width * 2 + 3) & ~3 }
        public var slotSize: Int { rowBytes * height }
        public var fileName: String { "F\(formatID)_1.ithmb" }
    }

    /// The first image identifier. Anything non-zero - zero in `mhit` 0x160
    /// means "no artwork". On the Classic the lowest is 101.
    public static let firstImageID: UInt32 = 100

    /// Random file identifiers: 16 B (`MhfdLayout.identity`) and 8 B (`MhfdLayout.secondIdentity`).
    public static func randomIdentity() -> [UInt8] {
        (0..<24).map { _ in UInt8.random(in: 0...255) }
    }

    /// A file with no images and the given formats.
    public static func empty(formats: [Format], identity: [UInt8]) -> Data {
        precondition(identity.count == 24, "ArtworkDB identifiers are 24 bytes")
        let formatRecords = formats.sorted { $0.formatID < $1.formatID }.flatMap(formatRecord)
        let sections = section(type: ArtworkSectionLayout.images, list: list("mhli", count: 0))
                     + section(type: ArtworkSectionLayout.albums, list: list("mhla", count: 0))
                     + section(type: ArtworkSectionLayout.formats, list: list("mhlf", count: formats.count) + formatRecords)

        var header = record("mhfd", headerLength: MhfdLayout.headerLength, total: MhfdLayout.headerLength + sections.count)
        header.set(MhfdLayout.version, 6)
        header.set(MhfdLayout.sectionCount, 3)
        header.set(MhfdLayout.nextImageID, firstImageID)
        header.replaceSubrange(MhfdLayout.identity, with: identity[0..<16])
        header.set(MhfdLayout.unknown30, 1)
        header.replaceSubrange(MhfdLayout.secondIdentity, with: identity[16..<24])
        return Data(header + sections)
    }

    /// An image record with all its variants. The identifier is filled in by
    /// `ArtworkDBEditor.insertingImage`, from the counter of the file it goes into.
    public static func imageRecord(
        ownerPersistentID: UInt64, sourceByteCount: UInt32, trackCount: UInt32,
        variants: [(format: Format, offset: UInt32)]
    ) -> [UInt8] {
        let children = variants.flatMap { variant(format: $0.format, offset: $0.offset) }
        var header = record("mhii", headerLength: MhiiLayout.headerLength, total: MhiiLayout.headerLength + children.count)
        header.set(MhiiLayout.childCount, UInt32(variants.count))
        header.set(MhiiLayout.ownerPersistentID, ownerPersistentID)
        header.set(MhiiLayout.sourceByteCount, sourceByteCount)
        header.set(MhiiLayout.trackCount, trackCount)
        header.set(MhiiLayout.unknown3C, 1)
        header.set(MhiiLayout.unknown48, Double.nan.bitPattern)
        header.set(MhiiLayout.unknown50, Double.nan.bitPattern)
        return header + children
    }

    // MARK: - Records

    private static func variant(format: Format, offset: UInt32) -> [UInt8] {
        let name = fileNameRecord(":" + format.fileName)
        var mhni = record("mhni", headerLength: MhniLayout.headerLength, total: MhniLayout.headerLength + name.count)
        mhni.set(MhniLayout.childCount, 1)
        mhni.set(MhniLayout.formatID, format.formatID)
        mhni.set(MhniLayout.byteOffset, offset)
        mhni.set(MhniLayout.byteCount, UInt32(format.slotSize))
        mhni.set(MhniLayout.height, UInt16(format.height))
        mhni.set(MhniLayout.width, UInt16(format.width))
        mhni.set(MhniLayout.byteCountAgain, UInt32(format.slotSize))
        var container = record("mhod", headerLength: ArtworkMhodLayout.headerLength,
                               total: ArtworkMhodLayout.headerLength + mhni.count + name.count)
        container.set(ArtworkMhodLayout.type, ArtworkMhodLayout.variantContainer)
        return container + mhni + name
    }

    private static func fileNameRecord(_ name: String) -> [UInt8] {
        let characters = Array(name.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        let prefix = ArtworkMhodLayout.Text.start
        var mhod = record("mhod", headerLength: ArtworkMhodLayout.headerLength,
                          total: ArtworkMhodLayout.headerLength + prefix + characters.count)
        mhod.set(ArtworkMhodLayout.type, ArtworkMhodLayout.fileName)
        var body = [UInt8](repeating: 0, count: prefix)
        body.set(ArtworkMhodLayout.Text.byteCount, UInt32(characters.count))
        body.set(ArtworkMhodLayout.Text.encoding, 2)   // UTF-16LE
        return mhod + body + characters
    }

    private static func formatRecord(_ format: Format) -> [UInt8] {
        var mhif = record("mhif", headerLength: MhifLayout.headerLength, total: MhifLayout.headerLength)
        mhif.set(MhifLayout.formatID, format.formatID)
        mhif.set(MhifLayout.slotSize, UInt32(format.slotSize))
        return mhif
    }

    private static func section(type: UInt32, list: [UInt8]) -> [UInt8] {
        var mhsd = record("mhsd", headerLength: ArtworkSectionLayout.headerLength,
                          total: ArtworkSectionLayout.headerLength + list.count)
        mhsd.set(ArtworkSectionLayout.type, type)
        return mhsd + list
    }

    /// List header: at 0x08 the number of elements, not a length.
    private static func list(_ signature: String, count: Int) -> [UInt8] {
        record(signature, headerLength: ArtworkSectionLayout.listHeaderLength, total: count)
    }

    private static func record(_ signature: String, headerLength: Int, total: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: headerLength)
        bytes.replaceSubrange(0..<4, with: Array(signature.utf8))
        bytes.set(RecordLayout.headerLength, UInt32(headerLength))
        bytes.set(RecordLayout.totalLength, UInt32(total))
        return bytes
    }
}
