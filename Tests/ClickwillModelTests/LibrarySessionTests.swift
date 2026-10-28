import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Loading a library from one source - without the model and without views.
@Suite("Library session")
@MainActor
struct LibrarySessionTests {

    @Test("a backup from disk without Music: files cannot be checked, the Classic profile assumed")
    func snapshotWithoutMusic() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        let data = SyntheticLibrary.database()
        try data.write(to: itunes.appendingPathComponent("iTunesDB"))

        let session = try LibrarySession.open(.snapshot(root))
        #expect(session.device == nil)
        #expect(!session.canCheckFiles)
        #expect(session.missingFileIDs.isEmpty)
        #expect(session.capabilities.isAssumed)
        #expect(session.library.tracks.count == 7)
        #expect(session.sourceDigest == IPodDevice.digest(of: data))
    }

    @Test("a connected iPod: a missing file detected, the profile from the device")
    func deviceWithMissingFile() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(missingFile: 16)); defer { rig.cleanUp() }
        let session = try LibrarySession.open(try #require(rig.model.source))
        #expect(session.device != nil)
        #expect(session.canCheckFiles)
        #expect(session.missingFileIDs == [16])
        #expect(!session.capabilities.isAssumed)
    }

    @Test("after a write: a new library and digest; missing files recounted only after a file replacement")
    func adoptAfterWrite() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(missingFile: 16)); defer { rig.cleanUp() }
        var session = try LibrarySession.open(try #require(rig.model.source))
        try Data(repeating: 1, count: 10).write(to: rig.musicFile(16))
        let renamed = session.library.mappingTracks { $0.uniqueID == 10 ? $0.setting(.title, to: "New") : $0 }

        session.adopt(renamed, sourceDigest: "abc", filesReplaced: false)
        #expect(session.library.tracks.first { $0.uniqueID == 10 }?.title == "New")
        #expect(session.sourceDigest == "abc")
        #expect(session.missingFileIDs == [16])

        session.adopt(renamed, sourceDigest: "def", filesReplaced: true)
        #expect(session.missingFileIDs.isEmpty)
    }

    @Test("a failed load does not touch the previous library")
    func failedLoadKeepsSession() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let before = try #require(rig.model.session)
        let broken = rig.root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: broken.appendingPathComponent("files/iTunes"), withIntermediateDirectories: true)
        try Data("this is not a database".utf8).write(to: broken.appendingPathComponent("files/iTunes/iTunesDB"))

        await rig.model.load(.snapshot(broken))
        guard case .failed = rig.model.state else { Issue.record("stan: \(rig.model.state)"); return }
        #expect(rig.model.source == before.source)
        #expect(rig.model.library?.tracks.count == before.library.tracks.count)
    }

    @Test("disconnecting takes the whole session")
    func disconnectDropsSession() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        try FileManager.default.removeItem(at: rig.paths.control)
        #expect(rig.model.deviceDisconnected())
        #expect(rig.model.session == nil)
        #expect(rig.model.library == nil && rig.model.paths == nil && rig.model.source == nil)
        #expect(!rig.model.canCheckFiles)
    }
}
