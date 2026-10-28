import Foundation
import Testing
@testable import ITDBKit

/// A USB reset can swap the iPods' mount names during copying,
/// and two writes can go to one iPod at once.
@Suite("Volume identity and write exclusivity")
struct DeviceSafetyTests {

    private static func volume(uuid: String?) throws -> (IPodVolume, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("safety-\(UUID().uuidString)")
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.control, withIntermediateDirectories: true)
        return (IPodVolume(paths: paths, name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false,
                           volumeUUID: uuid), root)
    }

    @Test("the same volume passes, a different and a vanished one - a refusal")
    func stillMounted() throws {
        let actual = IPodVolume.currentUUID(at: FileManager.default.temporaryDirectory)
        let (same, root) = try Self.volume(uuid: actual)
        defer { try? FileManager.default.removeItem(at: root) }
        try same.ensureStillMounted()

        let (swapped, other) = try Self.volume(uuid: "00000000-0000-0000-0000-000000000000")
        defer { try? FileManager.default.removeItem(at: other) }
        #expect(throws: ITDBError.self) { try swapped.ensureStillMounted() }

        try FileManager.default.removeItem(at: root)
        #expect(throws: ITDBError.self) { try same.ensureStillMounted() }
    }

    @Test("a folder given by hand: an iPod only with iPod_Control, with the volume UUID underneath")
    func volumeAtPickedFolder() throws {
        let (_, root) = try Self.volume(uuid: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        let volume = try #require(IPodVolume.at(root))
        #expect(volume.mountPoint == root)
        #expect(volume.volumeUUID == IPodVolume.currentUUID(at: root))
        try volume.ensureStillMounted()

        let plain = FileManager.default.temporaryDirectory.appendingPathComponent("not-ipod-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        #expect(IPodVolume.at(plain) == nil)
    }

    @Test("a second write to the same iPod waits for the first to finish")
    func exclusiveLock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("locks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var first: DeviceWriteLock? = try DeviceWriteLock.acquire(identity: "000A2700198BD0A3", in: directory)
        #expect(throws: ITDBError.self) { try DeviceWriteLock.acquire(identity: "000A2700198BD0A3", in: directory) }
        _ = try DeviceWriteLock.acquire(identity: "000A27001234ABCD", in: directory)   // another iPod - allowed
        withExtendedLifetime(first) {}
        first = nil
        _ = try DeviceWriteLock.acquire(identity: "000A2700198BD0A3", in: directory)
    }
}
