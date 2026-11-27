import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

/// Whether the source keeps photos; only the folder is looked at.
@Suite("Photo presence")
@MainActor
struct PhotoPresenceTests {

    @Test("an iPod without a Photos folder has none, with one it has photos")
    func device() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let device = try #require(rig.model.device)
        let files = LocalFileSystem()
        #expect(rig.model.photos == .none)
        #expect(PhotoPresence.detect(for: .device(device), paths: device.paths, files: files) == .none)
        try FileManager.default.createDirectory(at: device.paths.photosDirectory, withIntermediateDirectories: true)
        #expect(PhotoPresence.detect(for: .device(device), paths: device.paths, files: files) == .present)
    }

    @Test("a backup never claims to know about photos")
    func backup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = IPodPaths(mountPoint: folder)
        #expect(PhotoPresence.detect(for: .snapshot(folder), paths: paths, files: LocalFileSystem()) == .notInBackup)
    }
}
