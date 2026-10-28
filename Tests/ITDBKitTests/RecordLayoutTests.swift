import Foundation
import Testing
@testable import ITDBKit

@Suite("Writing bytes and record layouts")
struct RecordLayoutTests {

    @Test("ByteWriter: little-endian in place, at the end and back")
    func byteWriter() {
        var bytes = [UInt8](repeating: 0, count: 8)
        #expect(ByteWriter.put(UInt32(0x1122_3344), at: 2, in: &bytes))
        #expect(bytes == [0, 0, 0x44, 0x33, 0x22, 0x11, 0, 0])
        #expect(ByteWriter.value(UInt32.self, at: 2, in: bytes) == 0x1122_3344)
        ByteWriter.append(UInt16(0xBEEF), to: &bytes)
        #expect(bytes.suffix(2) == [0xEF, 0xBE])
        var long = [UInt8](repeating: 0, count: 8)
        ByteWriter.put(UInt64(0x0102_0304_0506_0708), at: 0, in: &long)
        #expect(long == [8, 7, 6, 5, 4, 3, 2, 1])
    }

    @Test("a field beyond the array: writing changes nothing, reading gives nil")
    func outOfRange() {
        var bytes: [UInt8] = [1, 2, 3]
        #expect(!ByteWriter.put(UInt32(7), at: 1, in: &bytes))
        #expect(bytes == [1, 2, 3])
        #expect(bytes[HeaderField<UInt32>(1)] == nil)
        let written = bytes.set(HeaderField<UInt16>(2), 9)
        #expect(!written)
        #expect(bytes == [1, 2, 3])
    }

    /// All `MhitLayout` fields with names - for the checks below.
    static let mhitFields: [(String, Range<Int>)] = {
        typealias M = MhitLayout
        return [("mhodCount", M.mhodCount.range), ("uniqueID", M.uniqueID.range), ("visible", M.visible.range),
                ("fileTypeCode", M.fileTypeCode.range), ("type1", M.type1.range), ("mpegFlag", M.mpegFlag.range),
                ("compilation", M.compilation.range), ("rating", M.rating.range), ("dateModified", M.dateModified.range),
                ("sizeBytes", M.sizeBytes.range), ("durationMilliseconds", M.durationMilliseconds.range),
                ("trackNumber", M.trackNumber.range), ("totalTracks", M.totalTracks.range), ("year", M.year.range),
                ("bitRate", M.bitRate.range), ("sampleRate", M.sampleRate.range), ("playCount", M.playCount.range),
                ("unknown54", M.unknown54.range), ("lastPlayed", M.lastPlayed.range), ("discNumber", M.discNumber.range),
                ("totalDiscs", M.totalDiscs.range), ("dateAdded", M.dateAdded.range), ("persistentID", M.persistentID.range),
                ("artworkCount", M.artworkCount.range), ("artworkMarker", M.artworkMarker.range),
                ("artworkSourceSize", M.artworkSourceSize.range), ("sampleRateFloat", M.sampleRateFloat.range),
                ("unknown98", M.unknown98.range), ("unknown9C", M.unknown9C.range), ("unknownA0", M.unknownA0.range),
                ("artworkPresence", M.artworkPresence.range), ("secondaryPersistentID", M.secondaryPersistentID.range),
                ("albumRecordIndex", M.albumRecordIndex.range), ("sizeBytesSecondary", M.sizeBytesSecondary.range),
                ("losslessFlag", M.losslessFlag.range), ("artworkIdentifier", M.artworkIdentifier.range),
                ("uniqueIDPlusOne", M.uniqueIDPlusOne.range)]
    }()

    @Test("the mhit fields fit in the 624 B header and do not overlap")
    func mhitFieldsDisjoint() {
        for (name, range) in Self.mhitFields { #expect(range.upperBound <= 624, "\(name)") }
        let sorted = Self.mhitFields.sorted { $0.1.lowerBound < $1.1.lowerBound }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            #expect(left.1.upperBound <= right.1.lowerBound, "\(left.0) overlaps \(right.0)")
        }
    }

    /// The byte map document. It lives outside the source tree, so a checkout without it
    /// skips the two tests that compare the layouts with it.
    static let byteMap = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("docs/byte-map.md")
    static let hasByteMap = FileManager.default.fileExists(atPath: byteMap.path)

    /// Table rows from the byte map section whose heading starts with `heading`:
    /// offset -> width in bytes.
    static func mapRows(_ heading: String) throws -> [Int: Int] {
        let text = try String(contentsOf: byteMap, encoding: .utf8)
        guard let start = text.range(of: "\n" + heading) else { return [:] }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n#")?.lowerBound ?? rest.endIndex
        var rows: [Int: Int] = [:]
        for line in rest[..<end].split(separator: "\n") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "") }
            guard cells.count >= 2, cells[0].hasPrefix("0x"), let offset = Int(cells[0].dropFirst(2), radix: 16),
                  let width = Int(cells[1]) else { continue }
            rows[offset] = width
        }
        return rows
    }

    private func expectInMap(_ heading: String, _ fields: [(String, Range<Int>)]) throws {
        let rows = try Self.mapRows(heading)
        #expect(!rows.isEmpty, "no section \(heading) in the byte map")
        for (name, range) in fields {
            #expect(rows[range.lowerBound] == range.count,
                    "\(name): 0x\(String(range.lowerBound, radix: 16, uppercase: true)) in the map \(rows[range.lowerBound].map(String.init) ?? "none"), in the layout \(range.count)")
        }
    }

    /// The byte map is the source of knowledge about the format: every layout field must have
    /// a row in it with the same offset and width.
    @Test("every mhit field is in the byte map with the same offset and width",
          .enabled(if: hasByteMap, "the byte map is not in this checkout"))
    func mhitFieldsMatchMap() throws {
        try expectInMap("## `mhit`", Self.mhitFields)
    }

    /// The child count fields (0x0C) and the NaN count fields (0x48, 0x50 - one row
    /// in the map) are described differently by the map; here we check the fields with rows of their own.
    @Test("the ArtworkDB fields (mhfd, mhii, mhni) are in the map with the same offset and width",
          .enabled(if: hasByteMap, "the byte map is not in this checkout"))
    func artworkFieldsMatchMap() throws {
        try expectInMap("### `mhfd`", [("version", MhfdLayout.version.range), ("sectionCount", MhfdLayout.sectionCount.range),
                                        ("nextImageID", MhfdLayout.nextImageID.range), ("identity", MhfdLayout.identity),
                                        ("unknown30", MhfdLayout.unknown30.range), ("secondIdentity", MhfdLayout.secondIdentity)])
        try expectInMap("### `mhii`", [("imageID", MhiiLayout.imageID.range), ("ownerPersistentID", MhiiLayout.ownerPersistentID.range),
                                        ("sourceByteCount", MhiiLayout.sourceByteCount.range), ("trackCount", MhiiLayout.trackCount.range),
                                        ("unknown3C", MhiiLayout.unknown3C.range)])
        try expectInMap("### `mhni`", [("formatID", MhniLayout.formatID.range), ("byteOffset", MhniLayout.byteOffset.range),
                                        ("byteCount", MhniLayout.byteCount.range), ("height", MhniLayout.height.range),
                                        ("width", MhniLayout.width.range), ("byteCountAgain", MhniLayout.byteCountAgain.range)])
    }
}
