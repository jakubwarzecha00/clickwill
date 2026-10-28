import Foundation
import ITDBKit

/// `info` - information about the connected iPod.
enum InfoCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let volume = device.volume
        report("Device", [
            ("volume", "\(volume.name)  (\(volume.mountPoint.path))"),
            ("capacity", "\(formatted(bytes: volume.totalCapacity)), used \(formatted(bytes: volume.usedCapacity)), free \(formatted(bytes: volume.availableCapacity))"),
            ("FireWire GUID", device.fireWireID?.hex ?? "none (this device does not have one)"),
            ("GUID source", device.fireWireID?.source.rawValue ?? "-"),
            ("database format", "\(device.format.name), header \(device.format.headerLength) B, version \(device.format.version)"),
            ("model", "\(device.model.name) (source: \(device.model.source.rawValue))"),
            ("USB", device.usb.map { String(format: "0x%04X", $0.productID) + ($0.familyName.map { " - \($0)" } ?? " - not in the table") } ?? "not read"),
            ("writing", device.supportsWriting ? "allowed" : "BLOCKED - \(device.readOnlyReason?.description ?? "")"),
        ])
    }
}
