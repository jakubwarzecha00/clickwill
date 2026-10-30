import Foundation

/// Which GUID was read together with which database - so an iPod keeps its identity on a
/// connection where the registry doesn't give the USB serial number. Measured on the nano 2G:
/// one connection gave it, the next didn't, and backups and the experimental
/// permission of the same iPod ended up under two names.
///
/// `~/Library/Application Support/<product>/Devices/identities.json`. Kept on the Mac only.
/// An entry applies only to the same USB product: a database copied onto another model
/// doesn't take over the first one's identity.
public struct DeviceAliasStore: Sendable {
    public let file: URL

    public init(file: URL) { self.file = file }

    public static func standard(productName: String = ProductInfo.name) throws -> DeviceAliasStore {
        DeviceAliasStore(file: try ProductInfo.supportDirectory(named: productName)
            .appendingPathComponent("Devices", isDirectory: true).appendingPathComponent("identities.json"))
    }

    struct Entry: Codable, Equatable {
        let identity: String
        let usbProductID: UInt16?
    }

    /// With the GUID read: remembers it for this database. Without: the remembered one.
    public func resolve(_ device: IPodDevice) -> IPodDevice {
        var entries = load()
        let entry = Entry(identity: device.identity, usbProductID: device.usb?.productID)
        if device.fireWireID != nil {
            if entries[device.databaseIdentity] != entry {
                entries[device.databaseIdentity] = entry
                save(entries)
            }
            return device
        }
        guard let known = entries[device.databaseIdentity], known.usbProductID == device.usb?.productID else { return device }
        var resolved = device
        resolved.rememberedIdentity = known.identity
        return resolved
    }

    private func load() -> [String: Entry] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    private func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
