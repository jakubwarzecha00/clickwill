import Foundation
import Testing
@testable import ITDBKit

/// Builds a minimal ArtworkDB: mhfd + mhsd(1){mhli{mhii{mhod2{mhni{mhod3}}, mhod6}}} + mhsd(3){mhlf{mhif}}.
private func u32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
private func u64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * $0)) & 0xFF) } }
private func header(_ sig: String, _ length: Int, _ total: Int, _ fields: [Int: [UInt8]]) -> [UInt8] {
    var b = Array(sig.utf8) + u32(UInt32(length)) + u32(UInt32(total)) + [UInt8](repeating: 0, count: length - 12)
    for (o, v) in fields { b.replaceSubrange(o..<(o + v.count), with: v) }
    return b
}
private func sampleDB(format: UInt32 = 1060) -> Data {
    let name: [UInt8] = Array(":F\(format)_1.ithmb".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    let mhod3 = header("mhod", 24, 24 + 12 + name.count, [0x0C: u32(3)]) + u32(UInt32(name.count)) + u32(2) + u32(0) + name
    let mhni = header("mhni", 76, 76 + mhod3.count, [0x0C: u32(1), 0x10: u32(format), 0x14: u32(204800), 0x18: u32(204800), 0x20: [0x40, 0x01, 0x40, 0x01]]) + mhod3
    let mhod2 = header("mhod", 24, 24 + mhni.count, [0x0C: u32(2)]) + mhni
    let mhaf = header("mhaf", 96, 96, [:])
    let mhod6 = header("mhod", 24, 24 + mhaf.count, [0x0C: u32(6)]) + mhaf
    let mhii = header("mhii", 152, 152 + mhod2.count + mhod6.count, [0x0C: u32(2), 0x10: u32(101), 0x14: u64(0xAABB), 0x30: u32(777), 0x38: u32(9)]) + mhod2 + mhod6
    let mhli = header("mhli", 92, 92, [0x08: u32(1)])
    let mhsd1 = header("mhsd", 96, 96 + mhli.count + mhii.count, [0x0C: u32(1)]) + mhli + mhii
    let mhif = header("mhif", 124, 124, [0x10: u32(format), 0x14: u32(204800)])
    let mhlf = header("mhlf", 92, 92, [0x08: u32(1)])
    let mhsd3 = header("mhsd", 96, 96 + mhlf.count + mhif.count, [0x0C: u32(3)]) + mhlf + mhif
    let body = mhsd1 + mhsd3
    let mhfd = header("mhfd", 132, 132 + body.count, [0x14: u32(2), 0x1C: u32(102)])
    return Data(mhfd + body)
}

@Suite("ArtworkDB editor")
struct ArtworkDBEditorTests {

    @Test("a new mhii from a template: fields, offset, counters; the rest byte for byte")
    func addImage() throws {
        let original = sampleDB()
        let before = try ArtworkDBParser.parse(original)
        #expect(before.images.count == 1)

        let result = try ArtworkDBEditor.addingImage(
            to: original,
            image: .init(trackPersistentID: 0xCCDD, sourceByteCount: 4242, trackCount: 3, slotOffsets: [1060: 409600]))
        #expect(result.imageID == 102)
        let after = try ArtworkDBParser.parse(result.data)
        #expect(after.images.count == 2)
        let added = try #require(after.images.last)
        #expect(added.id == 102)
        #expect(added.trackPersistentID == 0xCCDD)
        #expect(added.variants.map(\.byteOffset) == [409600])
        #expect(added.variants.first?.width == 320)
        #expect(added.variants.first?.plainFileName == "F1060_1.ithmb")
        #expect([UInt8](result.data)[MhfdLayout.nextImageID] == 103)
        #expect([UInt8](result.data)[RecordLayout.totalLength] == UInt32(result.data.count))
        // The old image untouched, the format section moved as a whole.
        #expect(after.images.first?.id == 101)
        #expect(after.images.first?.variants.first?.byteOffset == 204800)
        #expect(after.formats == before.formats)
        // The template and the format section byte for byte; only the counters changed.
        let templateStart = 132 + 96 + 92, templateLength = 152 + 164 + 120
        #expect(result.data[templateStart..<(templateStart + templateLength)] == original[templateStart..<(templateStart + templateLength)])
        #expect(result.data.suffix(96 + 92 + 124) == original.suffix(96 + 92 + 124))
        #expect(result.data.count == original.count + templateLength)
    }

    @Test("no offset for the template's format - a refusal")
    func missingFormat() {
        #expect(throws: (any Error).self) {
            try ArtworkDBEditor.addingImage(to: sampleDB(), image: .init(trackPersistentID: 1, sourceByteCount: 1, trackCount: 1, slotOffsets: [:]))
        }
    }
}

@Suite("First artwork on a device (temporary folder)")
struct ArtworkAdditionTests {

    @Test("slots at the end of the file, the new mhii points to them, a render error rolls back the appended bytes")
    func addOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artadd-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try sampleDB().write(to: paths.artworkDB)
        // One existing 1060 slot (204800 B) - the template points to offset 204800, so the file has two slots.
        let ithmb = paths.artworkDirectory.appendingPathComponent("F1060_1.ithmb")
        try Data(repeating: 0x11, count: 2 * 204800).write(to: ithmb)

        let white = ITHMBImage(width: 320, height: 320, rgba: [UInt8](repeating: 255, count: 320 * 320 * 4))
        let outcome = try ArtworkAddition.add(ownerPersistentID: 0xBEEF, sourceByteCount: 10, trackCount: 4, in: paths) { _, _ in white }
        #expect(outcome.imageID == 102)
        #expect(outcome.slotOffsets == [1060: 2 * 204800])
        let file = try Data(contentsOf: ithmb)
        #expect(file.count == 3 * 204800)
        #expect(file[2 * 204800] == 0xFF && file[2 * 204800 + 1] == 0xFF)   // white in RGB565 = 0xFFFF
        let db = try ArtworkDBParser.parse(try Data(contentsOf: paths.artworkDB))
        #expect(db.images.count == 2)
        #expect(db.images.last?.trackPersistentID == 0xBEEF)
        let newOffset: UInt32 = try #require(db.images.last?.variants.first?.byteOffset)
        #expect(newOffset == 409_600)
        let listing = try FileManager.default.contentsOfDirectory(atPath: paths.artworkDirectory.path)
        #expect(listing.count == 2)   // no temporary files

        // A bad render -> the file goes back to 3 slots, the database without a third image.
        #expect(throws: (any Error).self) {
            try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths) { _, _ in
                ITHMBImage(width: 1, height: 1, rgba: [0, 0, 0, 255])
            }
        }
        let afterFailure = try Data(contentsOf: ithmb)
        #expect(afterFailure.count == 3 * 204800)
        let dbAfter = try ArtworkDBParser.parse(try Data(contentsOf: paths.artworkDB))
        #expect(dbAfter.images.count == 2)
    }

    @Test("an artwork format not measured on hardware - a refusal before touching the files")
    func unconfirmedFormatRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artadd2-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // 1031 (42x42 nano 2G) - described by the firmware, but we have not seen it on screen yet.
        let original = sampleDB(format: 1031)
        try original.write(to: paths.artworkDB)
        #expect(throws: (any Error).self) {
            try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths) { w, h in
                ITHMBImage(width: w, height: h, rgba: [UInt8](repeating: 255, count: w * h * 4))
            }
        }
        #expect(try Data(contentsOf: paths.artworkDB) == original)
        #expect(!FileManager.default.fileExists(atPath: paths.artworkDirectory.appendingPathComponent("F1031_1.ithmb").path))
    }

    @Test("mhia: the artwork owner pointer")
    func albumLink() throws {
        var header = [UInt8](repeating: 0, count: 88)
        header.replaceSubrange(0..<4, with: Array("mhia".utf8))
        let album = ITAlbum(index: 1, persistentID: 7, title: "X", artist: nil, sortArtist: nil, mhods: [], rawHeader: header)
        #expect(album.artworkOwnerPersistentID == 0)
        var changed = album
        changed.artworkOwnerPersistentID = 0x0102030405060708
        #expect(changed.artworkOwnerPersistentID == 0x0102030405060708)
        #expect(changed.rawHeader[0x20] == 0x08 && changed.rawHeader[0x27] == 0x01)
    }
}

@Suite("Artwork coverage in mhii")
struct ArtworkTrackCountTests {

    @Test("reading and replacing 0x38 touch nothing but that word")
    func setsOnlyTheCount() throws {
        let data = sampleDB()
        let before = try ArtworkDBEditor.trackCounts(in: data)
        let target = try #require(before.first)

        let after = try ArtworkDBEditor.settingTrackCounts([target.imageID: 13], in: data)
        #expect(after.count == data.count)

        let counts = try ArtworkDBEditor.trackCounts(in: after)
        #expect(counts.first?.trackCount == 13)
        #expect(counts.map(\.imageID) == before.map(\.imageID))
        #expect(counts.map(\.ownerPersistentID) == before.map(\.ownerPersistentID))

        // Everything except the four bytes must stay untouched.
        let differing = zip([UInt8](data), [UInt8](after)).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(differing.count <= 4)
    }

    @Test("a record outside the map stays unchanged")
    func untouchedRecordsKeepTheirCount() throws {
        let data = sampleDB()
        let before = try ArtworkDBEditor.trackCounts(in: data)
        let after = try ArtworkDBEditor.settingTrackCounts([999_999: 7], in: data)
        #expect(after == data)
        #expect(try ArtworkDBEditor.trackCounts(in: after).map(\.trackCount) == before.map(\.trackCount))
    }

    @Test("the image owner moved to the copy that stays - only 0x14")
    func reownsTheImage() throws {
        let data = sampleDB()
        let outcome = try ArtworkDBEditor.settingOwners([0xAABB: 0xCCDD], in: data)
        #expect(outcome.changed == 1)
        #expect(outcome.data.count == data.count)
        #expect(try ArtworkDBEditor.trackCounts(in: outcome.data).first?.ownerPersistentID == 0xCCDD)
        #expect(try ArtworkDBParser.parse(outcome.data).images.first?.trackPersistentID == 0xCCDD)
        let differing = zip([UInt8](data), [UInt8](outcome.data)).filter { $0.0 != $0.1 }
        #expect(differing.count <= 8)
    }

    @Test("another track's image stays with its owner")
    func otherOwnersStay() throws {
        let data = sampleDB()
        let outcome = try ArtworkDBEditor.settingOwners([0x1234: 0xCCDD], in: data)
        #expect(outcome.changed == 0)
        #expect(outcome.data == data)
    }
}
