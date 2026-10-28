import Foundation
import Testing
@testable import ITDBKit

/// A GUID from a file on the iPod (without the USB registry, for example a disk image) is
/// accepted only when it signs this iPod's database.
@Suite("FireWire GUID from a file confirmed by the database signature")
struct FireWireGUIDTests {
    // Synthetic GUIDs - real device numbers do not go into the tests.
    static let right = "000A270011223344"
    static let other = "000A270055667788"

    /// An iPod in a temporary folder with a database signed with the key `right`.
    private static func signedIPod(sysInfoExtendedGUID: String? = nil) throws -> (IPodVolume, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("guid-\(UUID().uuidString)")
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        let signed = try Hash58.sign(ITunesDBWriter.serialize(try LibraryFixture.standard()),
                                     fireWireID: Hash58.fireWireID(fromHex: right))
        try signed.write(to: paths.iTunesDB)
        if let guid = sysInfoExtendedGUID {
            try FileManager.default.createDirectory(at: paths.sysInfoExtended.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let xml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>FireWireGUID</key><string>\(guid)</string></dict></plist>
                """
            try Data(xml.utf8).write(to: paths.sysInfoExtended)
        }
        return (try #require(IPodVolume.at(root)), root)
    }

    @Test("SysInfoExtended from this iPod - writing allowed without the USB registry")
    func sysInfoExtendedThatSigns() throws {
        let (volume, root) = try Self.signedIPod(sysInfoExtendedGUID: Self.right)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = try IPodDevice.open(volume)
        #expect(device.fireWireID?.hex == Self.right)
        #expect(device.fireWireID?.source == .sysInfoExtended)
        #expect(device.supportsWriting)
    }

    @Test("SysInfoExtended from another iPod - rejected, writing blocked with a reason")
    func sysInfoExtendedFromAnotherIPod() throws {
        let (volume, root) = try Self.signedIPod(sysInfoExtendedGUID: Self.other)
        defer { try? FileManager.default.removeItem(at: root) }
        let device = try IPodDevice.open(volume)
        #expect(device.fireWireID == nil)
        #expect(!device.supportsWriting)
        #expect(device.readOnlyReason?.description.contains(Self.other) == true)
    }
}
