import Foundation
import Testing
@testable import ITDBKit

/// The device description from the firmware. The layout as on a real nano 2G,
/// with the same deviation from the plist standard: a `<key>` inside an `<array>`.
@Suite("Device description from the firmware")
struct DeviceDescriptionTests {

    static let nanoLikeXML = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict>
    <key>AlbumArt</key>
    <array>
    <key>1031</key>
    <dict><key>FormatId</key><integer>1031</integer><key>PixelFormat</key><string>4C353635</string>
    <key>RenderHeight</key><integer>42</integer><key>RenderWidth</key><integer>42</integer></dict>
    <key>1027</key>
    <dict><key>FormatId</key><integer>1027</integer><key>PixelFormat</key><string>4C353635</string>
    <key>RenderHeight</key><integer>100</integer><key>RenderWidth</key><integer>100</integer></dict>
    </array>
    <key>FamilyID</key><integer>9</integer>
    <key>UpdaterFamilyID</key><integer>19</integer>
    <key>FireWireGUID</key><string>000a27000000aa01</string>
    <key>SerialNumber</key><string>5U1000AAVQ5</string>
    <key>VisibleBuildID</key><string>1.1.3</string>
    </dict></plist>
    """.utf8)

    @Test("artwork formats, the GUID and the family from the nano 2G description")
    func parsesNanoDescription() throws {
        let info = try DeviceDescription.parse(xml: Self.nanoLikeXML)
        let expected = [
            DeviceDescription.ImageFormat(formatID: 1031, width: 42, height: 42, pixelFormat: "L565"),
            DeviceDescription.ImageFormat(formatID: 1027, width: 100, height: 100, pixelFormat: "L565"),
        ]
        #expect(info.albumArt == expected)
        let allLittleEndian = info.albumArt.allSatisfy { $0.isLittleEndianRGB565 }
        #expect(allLittleEndian)
        #expect(info.fireWireGUID == "000A27000000AA01")
        #expect(info.familyID == 9)
        #expect(info.updaterFamilyID == 19)
        #expect(info.serialNumber == "5U1000AAVQ5")
        #expect(info.firmwareVersion == "1.1.3")
        #expect(info.modelNumber == nil, "the nano 2G does not give ModelNumStr")
    }

    @Test("the pixel format code")
    func pixelFormatCodes() {
        #expect(DeviceDescription.fourCharacterCode("4C353635") == "L565")
        #expect(DeviceDescription.fourCharacterCode("42353635") == "B565")
        #expect(DeviceDescription.fourCharacterCode("zzz") == "zzz")
    }

    @Test("a firmware GUID different from the signing key blocks writing")
    func guidMismatchBlocksWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desc-\(UUID().uuidString)")
        let format = DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .hash58)
        let guid = FireWireGUID.Resolved(hex: "000A27001234ABCD", bytes: try Hash58.fireWireID(fromHex: "000A27001234ABCD"),
                                         source: .ioRegistry)
        func device(firmwareGUID: String) throws -> IPodDevice {
            let xml = String(decoding: Self.nanoLikeXML, as: UTF8.self)
                .replacingOccurrences(of: "000a27000000aa01", with: firmwareGUID)
            return IPodDevice(volume: IPodVolume(paths: IPodPaths(mountPoint: root), name: "iPod", totalCapacity: 1,
                                                 availableCapacity: 1, isReadOnly: false),
                              fireWireID: guid, format: format,
                              model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly),
                              usb: USBIdentity(productID: 0x1261),
                              firmwareDescription: try DeviceDescription.parse(xml: Data(xml.utf8)))
        }
        let agreeing = try device(firmwareGUID: "000A27001234ABCD")
        #expect(agreeing.supportsWriting)
        let mismatched = try device(firmwareGUID: "000A27005678EF01")
        #expect(!mismatched.supportsWriting)
        #expect(mismatched.readOnlyReason?.description.contains("000A27005678EF01") == true)
    }

    @Test("an unsigned database: writing only when USB and the firmware confirm a nano 2G")
    func unsignedNeedsBothConfirmations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("unsigned-\(UUID().uuidString)")
        let format = DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .presumedUnsigned)
        let nano = try DeviceDescription.parse(xml: Self.nanoLikeXML)
        let classicXML = String(decoding: Self.nanoLikeXML, as: UTF8.self)
            .replacingOccurrences(of: "<integer>9</integer>", with: "<integer>11</integer>")
        let otherFamily = try DeviceDescription.parse(xml: Data(classicXML.utf8))
        func device(_ usb: USBIdentity?, _ description: DeviceDescription?) -> IPodDevice {
            IPodDevice(volume: IPodVolume(paths: IPodPaths(mountPoint: root), name: "iPod", totalCapacity: 1,
                                          availableCapacity: 1, isReadOnly: false),
                       fireWireID: nil, format: format,
                       model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly),
                       usb: usb, firmwareDescription: description)
        }
        let confirmed = device(USBIdentity(productID: 0x1260), nano)
        #expect(confirmed.supportsWriting)
        #expect(confirmed.readOnlyReason == nil)
        #expect(confirmed.signer.format.signing == .presumedUnsigned)

        #expect(!device(nil, nano).supportsWriting, "without USB there is no second confirmation")
        #expect(!device(USBIdentity(productID: 0x1260), nil).supportsWriting, "without the firmware description neither")
        #expect(!device(USBIdentity(productID: 0x1260), otherFamily).supportsWriting)
        let conflicted = device(USBIdentity(productID: 0x1261), nano)
        #expect(!conflicted.supportsWriting, "USB says hash58, the database is unsigned")
        #expect(conflicted.readOnlyReason?.description.contains("scheme 1") == true)
    }

    @Test("an unsigned database: signing means no change, but only after confirmation and only with scheme 0")
    func unsignedSigner() throws {
        var bytes = [UInt8](ITunesDBWriter.serialize(try LibraryFixture.standard()))
        bytes[0x30] = 0; bytes[0x31] = 0
        let unsigned = Data(bytes)
        let format = try DatabaseFormat.detect(header: unsigned)
        #expect(format.signing == .presumedUnsigned)

        let confirmed = DatabaseSigner(format: format, fireWireID: nil, unsignedConfirmed: true)
        #expect(try confirmed.sign(unsigned) == unsigned)
        #expect(try confirmed.verify(unsigned))
        #expect(throws: ITDBError.self) { try DatabaseSigner(format: format, fireWireID: nil).sign(unsigned) }

        bytes[0x30] = 1
        #expect(throws: ITDBError.self, "assembling introduced a scheme - a refusal") { try confirmed.sign(Data(bytes)) }
    }
}
