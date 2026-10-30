import Foundation
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import ITDBKit

/// Diagnostics: what decides that an unconfirmed model may be allowed experimental
/// writing, and how Rockbox sees embedded images.
@Suite("Diagnostics")
struct DiagnosticsTests {

    typealias Rig = WritePolicyTests.Rig

    @Test("an iPod Video with a database that rebuilds exactly: every required check passes")
    func videoPasses() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let result = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .standard), isMusicRunning: { false })
        #expect(result.requiredPassed, "\(result.reportLines)")
        #expect(!result.confirmedModel)
        #expect(result.allowsExperimentalWriting)
        #expect(result[.usb]?.detail == "0x1209 · iPod (5th generation) · unsigned family")
        #expect(result[.rebuild]?.detail.hasSuffix("byte-identical") == true)
        #expect(result[.firmwareDescription]?.status == .warning, "a missing description warns, doesn't fail")
        #expect(result[.firmwareDescription]?.weight == .advisory)
    }

    @Test("the verdict says when the permission is already given")
    func verdictWithPermission() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let before = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .standard), isMusicRunning: { false })
        #expect(before.verdict.hasPrefix("Every required check passed"))
        let after = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .experimental), isMusicRunning: { false })
        #expect(after.verdict == "Experimental writing allowed for this iPod (permission given).")
    }

    @Test("a database that doesn't rebuild exactly: no permission")
    func notReproducedFails() throws {
        let rig = try WritePolicyTests.rig(database: try WritePolicyTests.paddedDatabase()); defer { rig.cleanUp() }
        let result = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .standard), isMusicRunning: { false })
        #expect(result[.rebuild]?.status == .failed)
        #expect(result[.rebuild]?.detail.contains("size differs") == true)
        #expect(!result.allowsExperimentalWriting)
    }

    @Test("no USB, a signed database, a confirmed model: no experimental permission")
    func otherCasesDontQualify() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        #expect(!Diagnostics.run(on: rig.device(nil, policy: .standard), isMusicRunning: { false }).allowsExperimentalWriting)
        #expect(!Diagnostics.run(on: rig.device(USBIdentity(productID: 0x1261), policy: .standard), isMusicRunning: { false })
            .allowsExperimentalWriting, "identity conflict")
        var nano = rig.device(USBIdentity(productID: 0x1260), policy: .standard)
        nano.firmwareDescription = try DeviceDescription.parse(xml: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>FamilyID</key><integer>9</integer></dict></plist>
            """.utf8))
        let confirmed = Diagnostics.run(on: nano, isMusicRunning: { false })
        #expect(confirmed.confirmedModel)
        #expect(!confirmed.allowsExperimentalWriting, "already writes, nothing to allow")
    }

    @Test("Music running and pending plays warn without blocking the permission")
    func advisoryChecks() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let result = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .standard), isMusicRunning: { true })
        #expect(result[.music]?.status == .warning)
        #expect(result.allowsExperimentalWriting)
    }

    @Test("the report carries no GUID")
    func reportWithoutGUID() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        var device = rig.device(USBIdentity(productID: 0x1260), policy: .standard)
        device.firmwareDescription = try DeviceDescription.parse(xml: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>FireWireGUID</key><string>000A27001234ABCD</string></dict></plist>
            """.utf8))
        let lines = Diagnostics.run(on: device, isMusicRunning: { false }).reportLines.joined()
        #expect(!lines.contains("000A27001234ABCD"))
    }

    // MARK: - Rockbox

    static func encoded(_ type: UTType, progressive: Bool = false) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = progressive
            ? [kCGImagePropertyJFIFDictionary: [kCGImagePropertyJFIFIsProgressive: true]] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("embedded images as Rockbox shows them: baseline JPEG yes, progressive JPEG and PNG no")
    func rockboxImages() throws {
        #expect(RockboxImage(try Self.encoded(.jpeg)) == .jpeg)
        #expect(RockboxImage(try Self.encoded(.jpeg, progressive: true)) == .progressiveJPEG)
        #expect(RockboxImage(try Self.encoded(.png)) == .png)
        #expect(RockboxImage(Data([0x47, 0x49, 0x46, 0x38])) == .other)
        // SOF0 with 12-bit samples: jpeg_load.c refuses precision other than 8.
        #expect(RockboxImage(Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 12, 0, 32, 0, 32, 3])) == .unsupportedJPEG)
        #expect(RockboxImage.jpeg.isShownByRockbox)
        #expect(!RockboxImage.png.isShownByRockbox)
    }

    @Test("Rockbox found by its folder, version and target from rockbox-info.txt")
    func rockboxInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rockbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(RockboxInstallation.detect(at: root) == nil)
        let folder = root.appendingPathComponent(".rockbox")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(RockboxInstallation.detect(at: root) == RockboxInstallation(version: nil, target: nil))
        try "Target: ipodvideo\nTarget id: 15\nVersion: f3ffe789ef-261030\n".write(
            to: folder.appendingPathComponent("rockbox-info.txt"), atomically: true, encoding: .utf8)
        #expect(RockboxInstallation.detect(at: root) == RockboxInstallation(version: "f3ffe789ef-261030", target: "ipodvideo"))
    }
}
