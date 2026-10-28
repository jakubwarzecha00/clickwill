import Foundation
import ITDBKit

/// `sysinfo [--out FILE]` - the iPod description from the firmware (VPD pages). Read-only;
/// `--out` writes the description XML to a file.
enum SysInfoCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        guard let info = device.firmwareDescription else { throw CommandError("the firmware gave no description (or this is not macOS)") }
        report("Firmware description", [
            ("serial number", info.serialNumber ?? "-"),
            ("FireWire GUID", info.fireWireGUID ?? "-"),
            ("GUID used for signing", device.fireWireID.map { "\($0.hex) (\($0.source.rawValue))" } ?? "-"),
            ("FamilyID / Updater", "\(info.familyID.map(String.init) ?? "-") / \(info.updaterFamilyID.map(String.init) ?? "-")"),
            ("firmware", info.firmwareVersion ?? "-"),
            ("ModelNumStr", info.modelNumber ?? "-"),
            ("XML", "\(info.xml.count) B"),
        ])
        for format in info.albumArt {
            print("  artwork \(format.formatID): \(format.width)x\(format.height) \(format.pixelFormat)")
        }
        if let conflict = device.identityConflict { print("  CONFLICT: \(conflict)") }
        if let path = call.value(for: "--out") {
            try? info.xml.write(to: URL(fileURLWithPath: path))
            print("  written: \(path)")
        }
    }
}
