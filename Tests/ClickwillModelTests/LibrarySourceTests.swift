import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

/// A snapshot from disk and the path check (ContainedPath): a volume made of links to `files/`
/// must not lose artwork, but a link outside the backup is still rejected.
@Suite("Snapshot from disk")
struct LibrarySourceTests {

    private func snapshot() throws -> (root: URL, outside: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-source-\(UUID().uuidString)", isDirectory: true)
        let artwork = base.appendingPathComponent("backup/files/Artwork", isDirectory: true)
        try FileManager.default.createDirectory(at: artwork, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("backup/files/iTunes"), withIntermediateDirectories: true)
        try Data("pixels".utf8).write(to: artwork.appendingPathComponent("F1055_1.ithmb"))
        let outside = base.appendingPathComponent("outside.ithmb")
        try Data("foreign".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: artwork.appendingPathComponent("F1055_2.ithmb"), withDestinationURL: outside)
        return (base.appendingPathComponent("backup", isDirectory: true), outside)
    }

    @Test("artwork from a backup passes the path check")
    func artworkInsideSnapshot() throws {
        let (root, _) = try snapshot(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let paths = try LibrarySource.snapshot(root).mount()
        #expect(paths.artworkFile("F1055_1.ithmb") != nil)
        #expect(paths.artworkFile("F1055_2.ithmb") == nil, "a link outside the backup is still rejected")
    }

    @Test("a volume from the 0.2.0 workaround (a link to the backup) is replaced with a plain folder")
    func replacesLegacySymlinkMount() throws {
        let (root, _) = try snapshot(); defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let mount = try LibrarySource.snapshot(root).mount().mountPoint
        try FileManager.default.removeItem(at: mount)
        try FileManager.default.createSymbolicLink(at: mount, withDestinationURL: root)

        let paths = try LibrarySource.snapshot(root).mount()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: mount.path)) == nil)
        #expect(paths.artworkFile("F1055_1.ithmb") != nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("iPod_Control").path), "nothing goes into the backup folder")
    }
}
