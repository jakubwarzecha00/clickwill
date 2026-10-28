import Foundation
import Testing
@testable import ITDBKit

/// Regressions for security audit 0.1.3: a path
/// from iPod or backup data must not lead a read, write or delete
/// outside the iPod. The same attacks the audit used to confirm the problem - only on
/// artificial files in a temporary folder - must now be rejected.
@Suite("Paths from iPod data stay on the iPod")
struct ContainedPathTests {

    /// `<root>/ipod/iPod_Control/{Artwork,Music/F00}` and a "private" file next to it, in `<root>`.
    private func fixture() throws -> (root: URL, paths: IPodPaths, secret: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-paths-\(UUID())")
        let paths = IPodPaths(mountPoint: root.appendingPathComponent("ipod"))
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.musicDirectory.appendingPathComponent("F00"), withIntermediateDirectories: true)
        let secret = root.appendingPathComponent("synthetic-private.bin")
        try Data([0x00, 0x00]).write(to: secret)
        return (root, paths, secret)
    }

    private func variant(_ fileName: String) -> ArtworkVariant {
        ArtworkVariant(correlationID: 9, fileName: fileName, byteOffset: 0, byteCount: 2, width: 1, height: 1)
    }

    // MARK: - Artwork

    @Test("artwork with .. in the name: the read rejected")
    func artworkTraversalRead() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ITDBError.self) { try ITHMB.read(variant(":../../../synthetic-private.bin"), in: paths) }
        #expect(throws: ITDBError.self) { try variant(":../../../synthetic-private.bin").url(in: paths) }
    }

    @Test("artwork with .. in the name: the write rejected, the file next to it untouched")
    func artworkTraversalWrite() throws {
        let (root, paths, secret) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: ITDBError.self) {
            try ArtworkReplacement.write([.init(variant: variant(":../../../synthetic-private.bin"))], in: paths) { _, _ in
                ITHMBImage(width: 1, height: 1, rgba: [255, 255, 255, 255])
            }
        }
        #expect(try Data(contentsOf: secret) == Data([0x00, 0x00]))
    }

    @Test("an artwork file that is a link pointing outside: read and write rejected")
    func artworkSymlinkedFile() throws {
        let (root, paths, secret) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: paths.artworkDirectory.appendingPathComponent("F9_1.ithmb"), withDestinationURL: secret)
        #expect(throws: ITDBError.self) { try ITHMB.read(variant(":F9_1.ithmb"), in: paths) }
        #expect(throws: ITDBError.self) {
            try ArtworkReplacement.write([.init(variant: variant(":F9_1.ithmb"))], in: paths) { _, _ in
                ITHMBImage(width: 1, height: 1, rgba: [255, 255, 255, 255])
            }
        }
        #expect(try Data(contentsOf: secret) == Data([0x00, 0x00]))
    }

    @Test("an Artwork folder that is a link pointing outside: rejected")
    func artworkSymlinkedDirectory() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data([0x00, 0xF8]).write(to: outside.appendingPathComponent("F9_1.ithmb"))
        try FileManager.default.removeItem(at: paths.artworkDirectory)
        try FileManager.default.createSymbolicLink(at: paths.artworkDirectory, withDestinationURL: outside)
        #expect(throws: ITDBError.self) { try ITHMB.read(variant(":F9_1.ithmb"), in: paths) }
    }

    @Test("a name outside the F<format>_<n>.ithmb pattern: rejected, even without ..")
    func artworkNamePattern() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in [":ArtworkDB", ":F9_1.ithmb/x", ":sub:F9_1.ithmb", ":F9_1.ithmb\0", ":"] {
            #expect(throws: ITDBError.self) { try variant(name).url(in: paths) }
        }
    }

    @Test("valid artwork is still read and written")
    func validArtworkStillWorks() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = paths.artworkDirectory.appendingPathComponent("F1060_1.ithmb")
        try Data([0x00, 0xF8]).write(to: file)
        let ok = ArtworkVariant(correlationID: 1060, fileName: ":F1060_1.ithmb", byteOffset: 0, byteCount: 2, width: 1, height: 1)
        #expect(try ITHMB.read(ok, in: paths).rgba == [255, 0, 0, 255])
        try ArtworkReplacement.write([.init(variant: ok)], in: paths) { _, _ in
            ITHMBImage(width: 1, height: 1, rgba: [255, 255, 255, 255])
        }
        #expect(try Data(contentsOf: file) == Data([0xFF, 0xFF]))
    }

    @Test("a slice with absurd dimensions: the read rejected")
    func artworkBounds() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0x00, 0xF8]).write(to: paths.artworkDirectory.appendingPathComponent("F9_1.ithmb"))
        let huge = ArtworkVariant(correlationID: 9, fileName: ":F9_1.ithmb", byteOffset: 0, byteCount: 0x7FFF_FFFF, width: 1, height: 1)
        #expect(throws: ITDBError.self) { try ITHMB.read(huge, in: paths) }
    }

    // MARK: - Tracks

    @Test("a track location with .. or outside Music: no file instead of the file next to it")
    func trackTraversal() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let track = try LibraryFixture.standard().tracks[0]
        for location in [":..:synthetic-private.bin", ":iPod_Control:Music:..:..:..:synthetic-private.bin",
                         ":iPod_Control:Artwork:ArtworkDB", ":iPod_Control:iTunes:iTunesDB", ":synthetic-private.bin"] {
            #expect(track.setting(.location, to: location).fileURL(on: paths) == nil, "\(location)")
        }
    }

    @Test("a track file that is a link pointing outside: no file")
    func trackSymlink() throws {
        let (root, paths, secret) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: paths.musicDirectory.appendingPathComponent("F00/LINK.mp3"), withDestinationURL: secret)
        let track = try LibraryFixture.standard().tracks[0].setting(.location, to: ":iPod_Control:Music:F00:LINK.mp3")
        #expect(track.fileURL(on: paths) == nil)
    }

    @Test("a valid track location still points to the file in Music")
    func validTrackStillWorks() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = paths.musicDirectory.appendingPathComponent("F00/ABCD.mp3")
        try Data([1]).write(to: file)
        let track = try LibraryFixture.standard().tracks[0].setting(.location, to: ":iPod_Control:Music:F00:ABCD.mp3")
        #expect(track.fileURL(on: paths)?.standardizedFileURL == file.standardizedFileURL)
    }

    @Test("a track added by Clickwill passes the check - adding still works")
    func addedTrackStillResolves() throws {
        let (root, paths, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("song.mp3")
        try Data(repeating: 1, count: 64).write(to: source)
        let placement = try FileReplacement.place(source, in: paths)
        let track = try LibraryFixture.standard().tracks[0]
            .setting(.location, to: ITTrack.databaseLocation(fromFilesystemPath: placement.relativePath))
        #expect(track.fileURL(on: paths)?.standardizedFileURL == placement.url.standardizedFileURL)
        // The folder for the replacement file: only `Fxx` from the old path.
        #expect(FileReplacement.directory(of: "iPod_Control/Music/F12/ABCD.mp3") == "F12")
        #expect(FileReplacement.directory(of: "iPod_Control/Music/F..x/ABCD.mp3") == nil)
        #expect(try FileReplacement.place(source, in: paths, preferredDirectory: "F..").relativePath.hasPrefix("iPod_Control/Music/F00/"))
    }

    // MARK: - Backups

    @Test("a path from a backup manifest: only iTunes/ and Artwork/, no ..")
    func snapshotManifestPaths() throws {
        let base = URL(fileURLWithPath: "/tmp/backup", isDirectory: true)
        #expect(SnapshotStore.contained("iTunes/iTunesDB", in: base) != nil)
        #expect(SnapshotStore.contained("Artwork/F1060_1.ithmb", in: base) != nil)
        for path in ["../iTunesDB", "iTunes/../../x", "Music/F00/A.mp3", "iTunes", "/etc/passwd", "iTunes//iTunesDB"] {
            #expect(SnapshotStore.contained(path, in: base) == nil, "\(path)")
        }
    }
}
