import Foundation
import Testing
@testable import ITDBKit

/// The second source of the expected signature. It makes sure a mismatch with the database
/// blocks writing, and having no opinion - does not.
@Suite("USB identity")
struct USBIdentityTests {

    @Test("Classic with a hash58 database: agreement")
    func classicAgrees() {
        #expect(USBIdentity(productID: 0x1261).conflict(withDatabaseScheme: 1) == nil)
    }

    @Test("nano 5G with a database taken for hash58: a conflict with the name and both schemes")
    func nano5GConflict() throws {
        let conflict = try #require(USBIdentity(productID: 0x1265).conflict(withDatabaseScheme: 1))
        #expect(conflict == .usbScheme(family: "iPod nano (5th generation)", expected: 2, database: 1))
    }

    @Test("nano 2G: unsigned, a hash58 database is a conflict")
    func nano2G() {
        #expect(USBIdentity(productID: 0x1260).expectedScheme == 0)
        #expect(USBIdentity(productID: 0x1260).conflict(withDatabaseScheme: 0) == nil)
        #expect(USBIdentity(productID: 0x1260).conflict(withDatabaseScheme: 1) != nil)
    }

    @Test("an identifier outside the table means no opinion, neither agreement nor objection")
    func unknownProduct() {
        let identity = USBIdentity(productID: 0x1247)   // Classic 7G recovery mode
        #expect(identity.expectedScheme == nil)
        #expect(identity.conflict(withDatabaseScheme: 1) == nil)
    }

    @Test("a conflict blocks writing on a device that would otherwise write")
    func conflictBlocksWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usb-\(UUID().uuidString)")
        let paths = IPodPaths(mountPoint: root)
        let format = DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .hash58)
        let guid = FireWireGUID.Resolved(hex: "000A27001234ABCD", bytes: try Hash58.fireWireID(fromHex: "000A27001234ABCD"), source: .sysInfo)
        func device(_ usb: USBIdentity?) -> IPodDevice {
            IPodDevice(volume: IPodVolume(paths: paths, name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                       fireWireID: guid, format: format,
                       model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly), usb: usb)
        }
        #expect(device(USBIdentity(productID: 0x1261)).supportsWriting)
        #expect(device(nil).supportsWriting, "without a second source the database decides, as before")
        let conflicted = device(USBIdentity(productID: 0x1265))
        #expect(!conflicted.supportsWriting)
        #expect(conflicted.readOnlyReason?.description.contains("nano (5th generation)") == true)
    }

    @Test("every format confirmed on hardware is writable: the Classic and a nano 3G by USB, and without USB the database decides")
    func confirmedFormatsAreWritable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("formats-\(UUID().uuidString)")
        let format = DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .hash58)
        let guid = FireWireGUID.Resolved(hex: "000A27001234ABCD", bytes: try Hash58.fireWireID(fromHex: "000A27001234ABCD"), source: .ioRegistry)
        func device(_ usb: USBIdentity?) -> IPodDevice {
            IPodDevice(volume: IPodVolume(paths: IPodPaths(mountPoint: root), name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                       fireWireID: guid, format: format,
                       model: IPodModel(modelNumber: nil, name: "iPod nano (3rd generation)", source: .usb), usb: usb)
        }
        #expect(device(USBIdentity(productID: 0x1261)).supportsWriting)
        #expect(device(USBIdentity(productID: 0x1262)).supportsWriting, "nano 3G: the same hash58 signature as the Classic")
        #expect(device(nil).supportsWriting, "without a second source the database decides")
    }

    @Test("the model from USB when SysInfo is silent - as on a Classic with an empty SysInfo")
    func modelFromUSB() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("usbm-\(UUID().uuidString)")
        let format = DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .hash58)
        let model = IPodModel.detect(paths: IPodPaths(mountPoint: root), format: format, usb: USBIdentity(productID: 0x1261))
        #expect(model.name == "iPod classic")
        #expect(model.source == .usb)
        #expect(model.isConfirmed)
    }
}
