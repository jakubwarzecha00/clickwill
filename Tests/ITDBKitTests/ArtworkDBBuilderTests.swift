import Foundation
import Testing
@testable import ITDBKit

/// `ArtworkDB` from scratch - for an iPod on which Finder did not create it (nano 2G).
@Suite("ArtworkDB from scratch")
struct ArtworkDBBuilderTests {

    static let nanoFormats = [
        DeviceDescription.ImageFormat(formatID: 1031, width: 42, height: 42, pixelFormat: "L565"),
        DeviceDescription.ImageFormat(formatID: 1027, width: 100, height: 100, pixelFormat: "L565"),
    ]

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + offset + $1]) << (8 * UInt32($1)) }
    }

    private static func temporaryPaths() throws -> IPodPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-new-\(UUID().uuidString)")
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        return paths
    }

    private static func solid(_ width: Int, _ height: Int) -> ITHMBImage {
        ITHMBImage(width: width, height: height, rgba: [UInt8](repeating: 200, count: width * height * 4))
    }

    @Test("slots with rows aligned to 4 bytes - matching those measured on the Classic")
    func slotSizes() {
        #expect(ArtworkDBBuilder.Format(formatID: 1061, width: 55, height: 55).slotSize == 6160)
        #expect(ArtworkDBBuilder.Format(formatID: 1055, width: 128, height: 128).slotSize == 32768)
        #expect(ArtworkDBBuilder.Format(formatID: 1060, width: 320, height: 320).slotSize == 204800)
        #expect(ArtworkDBBuilder.Format(formatID: 1027, width: 100, height: 100).slotSize == 20000)
        #expect(ArtworkDBBuilder.Format(formatID: 1031, width: 42, height: 42).slotSize == 3528)
    }

    @Test("an empty file: the header as Music writes it, formats ascending, zero images")
    func emptyDatabase() throws {
        let identity = (0..<24).map { UInt8($0 + 1) }
        let formats = Self.nanoFormats.compactMap(ArtworkDBBuilder.Format.init)
        let data = ArtworkDBBuilder.empty(formats: formats, identity: identity)

        #expect(Self.u32(data, 4) == 0x84)
        #expect(Int(Self.u32(data, 8)) == data.count)
        #expect(Self.u32(data, 0x10) == 6)
        #expect(Self.u32(data, 0x14) == 3)
        #expect(Self.u32(data, 0x1C) == ArtworkDBBuilder.firstImageID)
        #expect(Self.u32(data, 0x30) == 1)
        #expect(Array(data[0x20..<0x30]) == Array(identity[0..<16]))
        #expect(Array(data[0x3C..<0x44]) == Array(identity[16..<24]))

        let parsed = try ArtworkDBParser.parse(data)
        #expect(parsed.images.isEmpty)
        #expect(parsed.formats == [ArtworkFormat(correlationID: 1027, slotSize: 20000),
                                   ArtworkFormat(correlationID: 1031, slotSize: 3528)])
    }

    @Test("an image record: lengths as Music writes them, variant fields, the identifier from the counter")
    func imageRecord() throws {
        let format = ArtworkDBBuilder.Format(formatID: 1055, width: 128, height: 128)
        let record = ArtworkDBBuilder.imageRecord(ownerPersistentID: 0xAABB_CCDD_EEFF_0011, sourceByteCount: 125954,
                                                  trackCount: 13, variants: [(format, 32768)])
        // Music, format 1055: mhii 0x98 + mhod 164 (mhni 140, name 64).
        #expect(record.count == 0x98 + 164)

        let empty = ArtworkDBBuilder.empty(formats: [format], identity: [UInt8](repeating: 0, count: 24))
        let result = try ArtworkDBEditor.insertingImage(record, into: empty)
        #expect(result.imageID == ArtworkDBBuilder.firstImageID)
        #expect(Self.u32(result.data, 0x1C) == ArtworkDBBuilder.firstImageID + 1)

        let image = try #require(try ArtworkDBParser.parse(result.data).images.first)
        #expect(image.id == ArtworkDBBuilder.firstImageID)
        #expect(image.trackPersistentID == 0xAABB_CCDD_EEFF_0011)
        #expect(image.sourceByteCount == 125954)
        #expect(image.variants == [ArtworkVariant(correlationID: 1055, fileName: ":F1055_1.ithmb", byteOffset: 32768,
                                                  byteCount: 32768, width: 128, height: 128)])
    }

    @Test("first artwork without ArtworkDB: the file from the firmware formats, slots from zero, then from our own template")
    func firstCoverCreatesDatabase() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }

        let first = try ArtworkAddition.add(ownerPersistentID: 0x11, sourceByteCount: 1000, trackCount: 13, in: paths,
                                            deviceFormats: Self.nanoFormats, allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        #expect(first.createdDatabase)
        #expect(first.slotOffsets == [1027: 0, 1031: 0])
        let size = { (name: String) in
            (try? FileManager.default.attributesOfItem(atPath: paths.artworkDirectory.appendingPathComponent(name).path)[.size] as? Int) ?? -1
        }
        #expect(size("F1027_1.ithmb") == 20000)
        #expect(size("F1031_1.ithmb") == 3528)

        let second = try ArtworkAddition.add(ownerPersistentID: 0x22, sourceByteCount: 2000, trackCount: 10, in: paths,
                                             deviceFormats: Self.nanoFormats, allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        #expect(!second.createdDatabase)
        #expect(second.slotOffsets == [1027: 20000, 1031: 3528])
        #expect(second.imageID == first.imageID + 1)

        let artwork = try ArtworkDBParser.parse(try Data(contentsOf: paths.artworkDB))
        #expect(artwork.images.map(\.trackPersistentID) == [0x11, 0x22])
        let decoded = try ITHMB.read(try #require(artwork.images[1].variant(correlationID: 1031)), in: paths)
        #expect(decoded.width == 42 && decoded.height == 42)
        #expect(decoded.rgba[0] == 205, "the pixel comes back from the file, not from a zeroed slot")
    }

    @Test("the same image for the album's other tracks: an mhii per track, the same slots, the .ithmb files unchanged")
    func sharingImageWithTracks() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        let first = try ArtworkAddition.add(ownerPersistentID: 0x11, sourceByteCount: 1000, trackCount: 3, in: paths,
                                            deviceFormats: Self.nanoFormats, allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        let pixels = try Data(contentsOf: paths.artworkDirectory.appendingPathComponent("F1027_1.ithmb"))

        let created = try ArtworkAddition.sharing(imageID: first.imageID, withTracks: [0x11, 0x22, 0x33], in: paths)
        #expect(created == [0x22: first.imageID + 1, 0x33: first.imageID + 2], "the owner already has a record - no duplicate")
        #expect(try Data(contentsOf: paths.artworkDirectory.appendingPathComponent("F1027_1.ithmb")) == pixels)

        let artwork = try ArtworkDBParser.parse(try Data(contentsOf: paths.artworkDB))
        #expect(artwork.images.map(\.trackPersistentID) == [0x11, 0x22, 0x33])
        for image in artwork.images {
            #expect(image.variant(correlationID: 1027)?.byteOffset == 0)
            #expect(image.variant(correlationID: 1031)?.byteOffset == 0)
            #expect(Self.u32(Data(image.rawHeader), 0x30) == 1000)
        }
        #expect(try ArtworkAddition.sharing(imageID: first.imageID, withTracks: [0x22, 0x33], in: paths).isEmpty,
                "the second time there is nothing to add")
        #expect(throws: ITDBError.self) { try ArtworkAddition.sharing(imageID: 999, withTracks: [0x44], in: paths) }
    }

    @Test("without ArtworkDB and without formats from the firmware - a refusal, the folder is not created")
    func noFormatsNoDatabase() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        #expect(throws: ITDBError.self) {
            try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths,
                                    allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        }
        #expect(!FileManager.default.fileExists(atPath: paths.artworkDirectory.path))
    }

    @Test("an unconfirmed format without consent to a trial - a refusal before touching the files")
    func unverifiedFormatsNeedConsent() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        let formats = Self.nanoFormats + [DeviceDescription.ImageFormat(formatID: 1068, width: 128, height: 128, pixelFormat: "L565")]
        #expect(throws: ITDBError.self) {
            try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths,
                                    deviceFormats: formats) { Self.solid($0, $1) }
        }
        #expect(!FileManager.default.fileExists(atPath: paths.artworkDirectory.path))
    }

    @Test("the nano 2G formats are confirmed: first artwork without a trial, as the app adds it")
    func nanoFormatsNeedNoTrial() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        let added = try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths,
                                            deviceFormats: Self.nanoFormats) { Self.solid($0, $1) }
        #expect(added.createdDatabase)
        #expect(Set(added.slotOffsets.keys) == [1027, 1031])
    }

    @Test("an encoding other than L565 - a refusal even with consent to a trial")
    func bigEndianRefused() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        let formats = [DeviceDescription.ImageFormat(formatID: 1023, width: 176, height: 132, pixelFormat: "B565")]
        #expect(throws: ITDBError.self) {
            try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths,
                                    deviceFormats: formats, allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        }
        #expect(!FileManager.default.fileExists(atPath: paths.artworkDirectory.path))
    }

    @Test("a render error on the first artwork removes everything it created")
    func failedRenderLeavesNothing() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        var calls = 0
        #expect(throws: ITDBError.self) {
            try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths,
                                    deviceFormats: Self.nanoFormats, allowingUnverifiedFormats: true) { w, h in
                calls += 1
                guard calls == 1 else { throw ITDBError.writeRefused(.inconsistent("test")) }
                return Self.solid(w, h)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: paths.artworkDirectory.path))
    }

    @Test("the dimensions from ArtworkDB and from the firmware disagree - a refusal")
    func dimensionConflict() throws {
        let paths = try Self.temporaryPaths()
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        _ = try ArtworkAddition.add(ownerPersistentID: 1, sourceByteCount: 1, trackCount: 1, in: paths,
                                    deviceFormats: Self.nanoFormats, allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        let lying = [DeviceDescription.ImageFormat(formatID: 1027, width: 90, height: 90, pixelFormat: "L565"),
                     Self.nanoFormats[0]]
        #expect(throws: ITDBError.self) {
            try ArtworkAddition.add(ownerPersistentID: 2, sourceByteCount: 1, trackCount: 1, in: paths,
                                    deviceFormats: lying, allowingUnverifiedFormats: true) { Self.solid($0, $1) }
        }
    }
}
