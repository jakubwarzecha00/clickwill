import Foundation
import Testing
@testable import ITDBKit

/// One iPod, one identity: the registry gives the USB serial number on some connections only
/// (nano 2G), and the same iPod must not become a second device on the Mac.
@Suite("Device identity")
struct DeviceIdentityTests {

    static let guid = FireWireGUID.Resolved(hex: "000A270000000042", bytes: [0x00, 0x0A, 0x27, 0, 0, 0, 0, 0x42], source: .ioRegistry)

    static func nano(_ rig: WritePolicyTests.Rig, guid: FireWireGUID.Resolved?, product: UInt16 = 0x1260) -> IPodDevice {
        IPodDevice(volume: IPodVolume(paths: rig.paths, name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                   fireWireID: guid, format: DatabaseFormat(headerLength: 244, version: 117, databaseID: 7, signing: .presumedUnsigned),
                   model: IPodModel(modelNumber: nil, name: "iPod nano (2nd generation)", source: .usb),
                   usb: USBIdentity(productID: product))
    }

    @Test("the GUID seen once with a database names the iPod on a connection without it")
    func remembered() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let aliases = DeviceAliasStore(file: rig.root.appendingPathComponent("Devices/identities.json"))
        let without = Self.nano(rig, guid: nil)
        #expect(aliases.resolve(without).identity == "DB-0000000000000007", "nothing remembered yet")

        let with = aliases.resolve(Self.nano(rig, guid: Self.guid))
        #expect(with.identity == "000A270000000042")
        let later = aliases.resolve(without)
        #expect(later.identity == "000A270000000042")
        #expect(later.identities == ["000A270000000042", "DB-0000000000000007"])
        #expect(later.fireWireID == nil, "remembered for filing, never used as a signing key")

        #expect(aliases.resolve(Self.nano(rig, guid: nil, product: 0x1209)).identity == "DB-0000000000000007",
                "the same database on another model doesn't take the identity")
    }

    @Test("backups filed under both names are listed and pruned as one iPod")
    func backupsUnderBothNames() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let old = try rig.store.capture(from: Self.nano(rig, guid: nil), reason: .manual)
        let device = Self.nano(rig, guid: Self.guid)
        let new = try rig.store.capture(from: device, reason: .manual)
        #expect(old.deviceGUID != new.deviceGUID)
        #expect(try rig.store.list(deviceGUID: device.identity).count == 1, "the split that hid backups before 0.4.1")
        let both = try rig.store.list(deviceGUIDs: device.identities)
        #expect(Set(both.map(\.deviceGUID)) == [old.deviceGUID, new.deviceGUID])
        #expect((try? rig.store.snapshot(deviceGUIDs: device.identities, id: old.id)) != nil)

        let removed = rig.store.prune(deviceGUIDs: device.identities, retention: SnapshotRetention(days: 0, alwaysKeepNewest: 1),
                                      now: Date().addingTimeInterval(86_400))
        #expect(removed.count == 1, "one retention over both names, not one per name")
        #expect(try rig.store.list(deviceGUIDs: device.identities).count == 1)
    }
}
