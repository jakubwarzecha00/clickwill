import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The Mac's disk with two changes: it refuses to delete files in `Music` and counts
/// how many times folders were created.
private final class ProbingFileSystem: FileSystem, @unchecked Sendable {
    let local = LocalFileSystem()
    var refuseRemovalUnder: URL?
    var directoriesCreated = 0

    func fileExists(at url: URL) -> Bool { local.fileExists(at: url) }
    func isDirectory(at url: URL) -> Bool { local.isDirectory(at: url) }
    func isRegularFile(at url: URL) -> Bool { local.isRegularFile(at: url) }
    func contents(of url: URL) throws -> Data { try local.contents(of: url) }
    func size(of url: URL) -> Int64? { local.size(of: url) }
    func removeItem(at url: URL) throws {
        if let root = refuseRemovalUnder, url.path.hasPrefix(root.path) { throw CocoaError(.fileWriteNoPermission) }
        try local.removeItem(at: url)
    }
    func createDirectory(at url: URL) throws { directoriesCreated += 1; try local.createDirectory(at: url) }
    func symbolicLinkDestination(at url: URL) -> String? { local.symbolicLinkDestination(at: url) }
    func createSymbolicLink(at url: URL, to destination: URL) throws { try local.createSymbolicLink(at: url, to: destination) }
    var temporaryDirectory: URL { local.temporaryDirectory }
}

@Suite("File system port")
@MainActor
struct FileSystemPortTests {

    @Test("the disk refuses to delete: the database is written, the file stays on the iPod and in the queue for the next write")
    func refusedDeletionStaysQueued() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let files = ProbingFileSystem()
        files.refuseRemovalUnder = rig.paths.musicDirectory
        var environment = rig.environment
        environment.files = files
        let model = LibraryModel(environment: environment)
        await model.load(try #require(rig.model.source))
        let album = try #require(model.albums.first { $0.title == "The Bends" })
        let row = try #require(model.tracks(of: album).first)
        let file = try #require(model.fileURL(for: row))

        try model.deleteTrack(row, in: album)
        let outcome = try await model.apply()

        #expect(outcome.undeletedFiles == [file])
        #expect(model.changes.filesToDelete == [file], "waits for the next write")
        #expect(model.hasPendingChanges, "the bar must not say that nothing is pending")
        #expect(model.changes.log.map(\.kind) == [.filesLeftToDelete(files: 1)])
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!(try rig.onDisk()).tracks.contains { $0.uniqueID == row.id }, "the database written anyway")
    }

    @Test("the old file after a conversion could not be deleted: a separate problem, not a conversion error")
    func oldFileKeptAfterConversion() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let files = ProbingFileSystem()
        files.refuseRemovalUnder = rig.paths.musicDirectory
        var environment = rig.environment
        environment.files = files
        let model = LibraryModel(environment: environment)
        await model.load(try #require(rig.model.source))
        await model.formatScan?.value
        let album = try #require(model.albums.first { $0.title == "The Bends" })
        let row = try #require(model.tracks(of: album).first { $0.title == "Just" })
        try model.convertTrack(row, in: album, keepOriginalsIn: nil)

        let outcome = try await model.apply()

        #expect(outcome.convertedFiles == 1)
        #expect(outcome.conversionProblems.isEmpty, "the conversion succeeded: \(outcome.conversionProblems)")
        #expect(outcome.oldFileProblems.count == 1, "\(outcome.oldFileProblems)")
        guard case .notDeleted? = outcome.oldFileProblems.first?.reason else {
            Issue.record("\(outcome.oldFileProblems)"); return
        }
    }

    @Test("a backup from disk: links created once per opening, through the port")
    func snapshotMountedOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("port-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let files = ProbingFileSystem()

        let session = try LibrarySession.open(.snapshot(root), files: files)

        #expect(files.directoriesCreated == 1)
        #expect(session.library.tracks.count == 7)
        #expect(session.paths.mountPoint.path.hasPrefix(files.temporaryDirectory.path))
    }
}
