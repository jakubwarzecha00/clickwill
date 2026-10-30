import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The Experimental iPods switch, one permission per device and Developer Mode.
@Suite("Experimental permissions")
@MainActor
struct ExperimentalPermissionsTests {

    nonisolated static func video(firmware: String? = "1.3", identity databaseID: UInt64 = 7) throws -> IPodDevice {
        var device = IPodDevice(volume: IPodVolume(paths: IPodPaths(mountPoint: URL(fileURLWithPath: "/tmp/none")), name: "iPod",
                                                   totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                                fireWireID: nil,
                                format: DatabaseFormat(headerLength: 244, version: 117, databaseID: databaseID, signing: .presumedUnsigned),
                                model: IPodModel(modelNumber: nil, name: "iPod (5th generation)", source: .usb),
                                usb: USBIdentity(productID: 0x1209))
        if let firmware {
            device.firmwareDescription = try DeviceDescription.parse(xml: Data("""
                <?xml version="1.0" encoding="UTF-8"?>
                <plist version="1.0"><dict><key>VisibleBuildID</key><string>\(firmware)</string></dict></plist>
                """.utf8))
        }
        return device
    }

    /// Diagnostics as they come out on a fake that passes everything.
    static func passed() throws -> Diagnostics {
        let rig = try WritePolicyRig.make(); defer { rig.cleanUp() }
        return Diagnostics.run(on: rig.device, isMusicRunning: { false })
    }

    @Test("a permission given on a connection without the GUID holds on one with it")
    func permissionAcrossIdentities() throws {
        let permissions = ExperimentalPermissions(storage: .memory())
        permissions.isEnabled = true
        let without = try Self.video()
        try permissions.allow(without, diagnostics: try Self.passed())
        #expect(permissions.grants.first?.identity == without.databaseIdentity)

        var with = try Self.video()
        with = IPodDevice(volume: with.volume,
                          fireWireID: FireWireGUID.Resolved(hex: "000A270000000042", bytes: [0, 0x0A, 0x27, 0, 0, 0, 0, 0x42], source: .ioRegistry),
                          format: with.format, model: with.model, usb: with.usb, firmwareDescription: with.firmwareDescription)
        #expect(with.identity != without.identity)
        #expect(permissions.policy(for: with) == .experimental)
        try permissions.allow(with, diagnostics: try Self.passed())
        #expect(permissions.grants.count == 1, "allowing again replaces the permission under either name")
    }

    @Test("off by default: every device standard, nothing can be allowed")
    func offByDefault() throws {
        let permissions = ExperimentalPermissions(storage: .memory())
        #expect(!permissions.isEnabled)
        #expect(permissions.policy(for: try Self.video()) == .standard)
        #expect(throws: ExperimentalPermissions.PermissionError.switchOff) {
            try permissions.allow(try Self.video(), diagnostics: try Self.passed())
        }
    }

    @Test("a permission holds for the same device and firmware, and lapses after a firmware update")
    func perDeviceAndFirmware() throws {
        let permissions = ExperimentalPermissions(storage: .memory())
        permissions.isEnabled = true
        try permissions.allow(try Self.video(), diagnostics: try Self.passed())
        #expect(permissions.policy(for: try Self.video()) == .experimental)
        #expect(permissions.policy(for: try Self.video(firmware: "1.3.1")) == .standard)
        #expect(permissions.policy(for: try Self.video(identity: 8)) == .standard, "another iPod")
    }

    @Test("failed diagnostics can't be allowed")
    func checksMustPass() throws {
        let permissions = ExperimentalPermissions(storage: .memory())
        permissions.isEnabled = true
        let rig = try WritePolicyRig.make(padded: true); defer { rig.cleanUp() }
        #expect(throws: ExperimentalPermissions.PermissionError.checksFailed) {
            try permissions.allow(rig.device, diagnostics: Diagnostics.run(on: rig.device, isMusicRunning: { false }))
        }
    }

    @Test("turning the switch off takes back every permission, also after a restart")
    func switchOffRevokes() throws {
        let storage = ExperimentalPermissions.Storage.memory()
        let permissions = ExperimentalPermissions(storage: storage)
        permissions.isEnabled = true
        try permissions.allow(try Self.video(), diagnostics: try Self.passed())
        #expect(ExperimentalPermissions(storage: storage).grants.count == 1, "kept across launches")
        permissions.isEnabled = false
        #expect(permissions.grants.isEmpty)
        let reopened = ExperimentalPermissions(storage: storage)
        reopened.isEnabled = true
        #expect(reopened.policy(for: try Self.video()) == .standard)
    }

    @Test("Developer Mode gives every device the developer policy, without a switch")
    func developerMode() throws {
        let permissions = ExperimentalPermissions(storage: .memory())
        permissions.developerMode = true
        #expect(permissions.policy(for: try Self.video()) == .developer)
    }

    @Test("a pinned backup survives pruning")
    func pinnedBackupSurvives() {
        func snapshot(_ id: String, daysAgo: Double) -> Snapshot {
            Snapshot(id: id, createdAt: Date().addingTimeInterval(-daysAgo * 86_400), deviceGUID: "DB-7", volumeName: "iPod",
                     note: nil, reason: .beforeWrite(changes: 1), files: [], skipped: [])
        }
        let all = [snapshot("a", daysAgo: 1), snapshot("b", daysAgo: 2), snapshot("c", daysAgo: 3),
                   snapshot("d", daysAgo: 30), snapshot("first", daysAgo: 40)]
        var retention = SnapshotRetention.standard
        #expect(retention.expired(among: all).map(\.id) == ["d", "first"])
        retention.pinned = ["first"]
        #expect(retention.expired(among: all).map(\.id) == ["d"])
    }
}

/// An unsigned iPod Video fake on disk that passes diagnostics (or, padded, fails the rebuild).
struct WritePolicyRig {
    let root: URL
    let device: IPodDevice

    static func make(padded: Bool = false) throws -> WritePolicyRig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("permissions-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = [UInt8](ITunesDBWriter.serialize(try ITunesDBParser.parse(SyntheticLibrary.database())))
        bytes[0x30] = 0; bytes[0x31] = 0
        if padded {
            bytes += [1, 2, 3, 4]
            withUnsafeBytes(of: UInt32(bytes.count).littleEndian) { bytes.replaceSubrange(8..<12, with: $0) }
        }
        try Data(bytes).write(to: paths.iTunesDB)
        var device = try ExperimentalPermissionsTests.video()
        device = IPodDevice(volume: IPodVolume(paths: paths, name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                            fireWireID: nil, format: device.format, model: device.model, usb: device.usb,
                            firmwareDescription: device.firmwareDescription)
        return WritePolicyRig(root: root, device: device)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

extension ExperimentalPermissionsTests {
    @Test("a permission rests on a model the release confirms")
    func permissionOnConfirmedModel() throws {
        let permissions = ExperimentalPermissions(storage: .memory())
        permissions.isEnabled = true
        let rig = try WritePolicyRig.make(); defer { rig.cleanUp() }
        try permissions.allow(rig.device, diagnostics: Diagnostics.run(on: rig.device, isMusicRunning: { false }))
        #expect(permissions.policy(for: rig.device) == .experimental)

        // The same iPod, same USB and firmware version, once its family is on the confirmed list
        // (family 9 stands in for a family a later release adds): the permission still matches.
        var confirmed = rig.device
        confirmed.firmwareDescription = try DeviceDescription.parse(xml: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>VisibleBuildID</key><string>1.3</string><key>FamilyID</key><integer>9</integer></dict></plist>
            """.utf8))
        #expect(permissions.grant(for: confirmed) != nil)
        #expect(permissions.policy(for: confirmed) == .standard)
    }
}

/// The report's account of where the iPod's identity came from - the line that would have
/// shown a split identity at once.
@Suite("Report identity lines")
struct ReportIdentityTests {
    @Test("signing key and identity source, without the GUID")
    func identityLines() throws {
        var device = try ExperimentalPermissionsTests.video()
        #expect(DiagnosticReport.signingKey(device) == "not needed (unsigned database)")
        #expect(DiagnosticReport.identitySource(device) == "database identifier (no GUID read on this Mac)")
        device.rememberedIdentity = "000A270000000042"
        #expect(DiagnosticReport.identitySource(device) == "GUID remembered from an earlier connection, not read on this one")
        #expect(!DiagnosticReport.identitySource(device).contains("000A27"))
    }
}
