import Foundation
import Testing
@testable import ITDBKit

@Suite("Album artwork coverage")
struct ArtworkCoverageTests {

    /// An artwork database with one record for the given track, declaring `declared`
    /// tracks. The layout as in `ArtworkDBEditorTests`, only parametric.
    static func artworkDB(owner: UInt64, declared: UInt32, extra: (owner: UInt64, declared: UInt32)? = nil) -> Data {
        func u32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
        func u64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8((v >> (8 * $0)) & 0xFF) } }
        func header(_ sig: String, _ length: Int, _ total: Int, _ fields: [Int: [UInt8]]) -> [UInt8] {
            var b = Array(sig.utf8) + u32(UInt32(length)) + u32(UInt32(total)) + [UInt8](repeating: 0, count: length - 12)
            for (o, v) in fields { b.replaceSubrange(o..<(o + v.count), with: v) }
            return b
        }
        func image(id: UInt32, owner: UInt64, declared: UInt32) -> [UInt8] {
            let name: [UInt8] = Array(":F1060_1.ithmb".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
            let mhod3 = header("mhod", 24, 24 + 12 + name.count, [0x0C: u32(3)]) + u32(UInt32(name.count)) + u32(2) + u32(0) + name
            let mhni = header("mhni", 76, 76 + mhod3.count, [0x0C: u32(1), 0x10: u32(1060), 0x14: u32(id == 101 ? 0 : 204800), 0x18: u32(204800)]) + mhod3
            let mhod2 = header("mhod", 24, 24 + mhni.count, [0x0C: u32(2)]) + mhni
            return header("mhii", 152, 152 + mhod2.count,
                          [0x0C: u32(1), 0x10: u32(id), 0x14: u64(owner), 0x38: u32(declared)]) + mhod2
        }
        var images = image(id: 101, owner: owner, declared: declared)
        var count: UInt32 = 1
        if let extra { images += image(id: 102, owner: extra.owner, declared: extra.declared); count = 2 }
        let mhli = header("mhli", 92, 92, [0x08: u32(count)])
        let mhsd1 = header("mhsd", 96, 96 + mhli.count + images.count, [0x0C: u32(1)]) + mhli + images
        let mhfd = header("mhfd", 132, 132 + mhsd1.count, [0x14: u32(1), 0x1C: u32(103)])
        return Data(mhfd + mhsd1)
    }

    /// The fixture has three albums; we take the first track of the given one.
    static func owner(of album: String, in library: ITLibrary) throws -> UInt64 {
        try #require(library.tracks.first { $0.album == album }).persistentID
    }

    @Test("an image covering one track out of three is reported as incomplete")
    func partialCoverageReported() throws {
        let library = try LibraryFixture.standard()
        let data = Self.artworkDB(owner: try Self.owner(of: "The Bends", in: library), declared: 1)
        let albums = try ArtworkCoverage.audit(library: library, artworkDB: data)

        let bends = try #require(albums.first { $0.title == "The Bends" })
        #expect(bends.trackCount == 3)
        #expect(bends.declared == 1)
        #expect(!bends.isComplete)
        #expect(bends.isRepairable)
    }

    @Test("the repair raises the coverage to the track count")
    func repairRaisesCoverage() throws {
        let library = try LibraryFixture.standard()
        let data = Self.artworkDB(owner: try Self.owner(of: "The Bends", in: library), declared: 1)
        let outcome = try ArtworkCoverage.repairing(data, library: library)

        #expect(outcome.repaired.map(\.title) == ["The Bends"])
        let after = try ArtworkCoverage.audit(library: library, artworkDB: outcome.data)
        #expect(after.first { $0.title == "The Bends" }?.isComplete == true)
        #expect(outcome.data.count == data.count)
    }

    @Test("coverage larger than the album is straightened too")
    func repairLowersCoverage() throws {
        let library = try LibraryFixture.standard()
        let data = Self.artworkDB(owner: try Self.owner(of: "Currents", in: library), declared: 40)
        let outcome = try ArtworkCoverage.repairing(data, library: library)
        let after = try ArtworkCoverage.audit(library: library, artworkDB: outcome.data)
        #expect(after.first { $0.title == "Currents" }?.declared == 2)
    }

    @Test("without access to the pixels an album with several images stays untouched")
    func severalImagesLeftAlone() throws {
        let library = try LibraryFixture.standard()
        let bends = library.tracks.filter { $0.album == "The Bends" }
        let data = Self.artworkDB(owner: bends[0].persistentID, declared: 1,
                                  extra: (bends[1].persistentID, 1))
        let albums = try ArtworkCoverage.audit(library: library, artworkDB: data)
        let album = try #require(albums.first { $0.title == "The Bends" })

        #expect(album.declared == 2)
        #expect(album.imageIDs.count == 2)
        #expect(!album.isComplete)
        #expect(!album.isRepairable)

        let outcome = try ArtworkCoverage.repairing(data, library: library)
        #expect(outcome.repaired.isEmpty)
        #expect(outcome.data == data)
    }

    @Test("an album with full coverage is not touched")
    func completeCoverageUntouched() throws {
        let library = try LibraryFixture.standard()
        let data = Self.artworkDB(owner: try Self.owner(of: "Currents", in: library), declared: 2)
        let outcome = try ArtworkCoverage.repairing(data, library: library)
        #expect(outcome.repaired.isEmpty)
        #expect(outcome.data == data)
    }

    /// An album with several images stops being ambiguous when all of them
    /// carry the same pixels - that is what an album looks like after an artwork replacement, because
    /// the replacement overwrites every slot of the album.
    static func withITHMB(_ slots: [UInt8], _ body: (IPodPaths) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cover-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var file = Data()
        for byte in slots { file += Data(repeating: byte, count: 204800) }
        try file.write(to: paths.artworkDirectory.appendingPathComponent("F1060_1.ithmb"))
        try body(paths)
    }

    @Test("identical artwork: coverage settled despite several images")
    func identicalImagesRepaired() throws {
        let library = try LibraryFixture.standard()
        let bends = library.tracks.filter { $0.album == "The Bends" }
        let data = Self.artworkDB(owner: bends[0].persistentID, declared: 1, extra: (bends[1].persistentID, 1))

        try Self.withITHMB([0x7A, 0x7A]) { paths in
            let album = try #require(try ArtworkCoverage.audit(library: library, artworkDB: data, paths: paths)
                .first { $0.title == "The Bends" })
            #expect(album.imagesMatch)
            #expect(album.isRepairable)

            let outcome = try ArtworkCoverage.repairing(data, library: library, paths: paths)
            #expect(outcome.repaired.map(\.title) == ["The Bends"])
            let after = try #require(try ArtworkCoverage.audit(library: library, artworkDB: outcome.data, paths: paths)
                .first { $0.title == "The Bends" })
            #expect(after.isComplete)
            // The second image stays as it is, the first takes the surplus: 2 + 1 = 3.
            #expect(try ArtworkDBEditor.trackCounts(in: outcome.data).map(\.trackCount) == [2, 1])
        }
    }

    @Test("different artwork on one album is still left alone")
    func differingImagesLeftAlone() throws {
        let library = try LibraryFixture.standard()
        let bends = library.tracks.filter { $0.album == "The Bends" }
        let data = Self.artworkDB(owner: bends[0].persistentID, declared: 1, extra: (bends[1].persistentID, 1))

        try Self.withITHMB([0x7A, 0x0C]) { paths in
            let album = try #require(try ArtworkCoverage.audit(library: library, artworkDB: data, paths: paths)
                .first { $0.title == "The Bends" })
            #expect(!album.imagesMatch)
            #expect(!album.isRepairable)
            #expect(try ArtworkCoverage.repairing(data, library: library, paths: paths).repaired.isEmpty)
        }
    }
}
