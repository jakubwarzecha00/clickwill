import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Demo mode given when the model is created.
@Suite("Demo mode")
@MainActor
struct DemoModeTests {

    private func snapshot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)", isDirectory: true)
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        return root
    }

    @Test("a backup from disk shown as an iPod: editing allowed, classic profile recognized, writing refuses")
    func snapshotPresentedAsDevice() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(demo: DemoMode(blocksWrites: true, deviceDetail: "iPod classic · 160 GB"))
        await model.load(.snapshot(root))

        #expect(model.isWritable)
        #expect(!model.capabilities.isAssumed)
        #expect(model.demoDeviceDetail == "iPod classic · 160 GB")
        _ = try model.setAlbumField(try #require(model.albums.first), .genre, to: "Rock")
        await #expect(throws: WriteBlocked.demoCopy) { _ = try await model.apply() }
        #expect(model.hasPendingChanges, "the refusal does not lose the edits")
    }

    @Test("without a device description a backup stays a backup: read-only, profile assumed")
    func plainSnapshot() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(demo: DemoMode(blocksWrites: true))
        await model.load(.snapshot(root))
        #expect(!model.isWritable)
        #expect(model.capabilities.isAssumed)
    }

    @Test("a connected iPod in demo mode: edits in memory, writing blocked, the database untouched")
    func deviceWritesBlocked() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let before = try Data(contentsOf: rig.paths.iTunesDB)
        let model = LibraryModel(environment: rig.environment, demo: DemoMode(blocksWrites: true, deviceDetail: "ignored"))
        await model.load(try #require(rig.model.source))

        #expect(model.isWritable, "a real iPod - from the device")
        _ = try model.setAlbumField(try #require(model.albums.first), .genre, to: "Rock")
        await #expect(throws: WriteBlocked.demoCopy) { _ = try await model.apply() }
        #expect(try Data(contentsOf: rig.paths.iTunesDB) == before)
        #expect(try rig.backups.list(deviceGUID: WriteTests.guid).isEmpty, "no backup - a refusal before anything")
    }

    @Test("the iPod list from demo mode goes to the chooser")
    func choices() throws {
        let choice = try #require(IPodChoice(demoArgument: "/tmp/backup|iPod (Demo)|iPod classic|160|20"))
        let model = LibraryModel(demo: DemoMode(blocksWrites: true, choices: [choice]))
        #expect(model.connectedChoices.map(\.name) == ["iPod (Demo)"])
        #expect(model.demoChoices.count == 1)
    }

    @Test("demo mode turned off changes nothing")
    func off() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        #expect(!rig.model.writesBlocked)
        #expect(rig.model.demoDeviceDetail == nil)
        #expect(rig.model.demoChoices.isEmpty)
    }
}
