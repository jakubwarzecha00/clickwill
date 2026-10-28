import Foundation
import IOKit
import DiskArbitration

/// Reading the device's FireWire GUID - 16 hex characters without which we cannot compute the signature.
///
/// On an iPod Classic 7G the `Device/SysInfo` file is sometimes empty, and `SysInfoExtended`
/// may not exist at all. That is why the main source is the IORegistry, where the GUID
/// appears as the USB serial number, and files on disk serve only as a fallback.
public enum FireWireGUID {

    public enum Source: String, Sendable {
        case ioRegistry = "IORegistry (USB serial number)"
        case sysInfoExtended = "Device/SysInfoExtended"
        case sysInfo = "Device/SysInfo"
    }

    public struct Resolved: Sendable {
        public let hex: String
        public let bytes: [UInt8]
        public let source: Source
    }

    /// Tries successive sources, starting with the most reliable.
    public static func resolve(for volume: IPodVolume) throws -> Resolved {
        let attempts: [(Source, () -> String?)] = [
            (.ioRegistry, { fromIORegistry(mountPoint: volume.mountPoint) }),
            (.sysInfoExtended, { fromSysInfoExtended(at: volume.paths.sysInfoExtended) }),
            (.sysInfo, { fromSysInfo(at: volume.paths.sysInfo) }),
        ]
        for (source, read) in attempts {
            guard let raw = read(), let bytes = try? Hash58.fireWireID(fromHex: raw) else { continue }
            return Resolved(hex: normalized(raw), bytes: bytes, source: source)
        }
        throw ITDBError.fireWireIDUnavailable(volume: volume.name)
    }

    /// Whether the database is signed with a key from this GUID.
    public static func signs(_ fireWireID: [UInt8], _ database: Data) -> Bool {
        (try? Hash58.verify(database: database, fireWireID: fireWireID).matches) ?? false
    }

    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
            .uppercased()
    }

    // MARK: - IORegistry

    /// Volume -> BSD device -> up the IORegistry tree to the USB entry.
    public static func fromIORegistry(mountPoint: URL) -> String? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, mountPoint as CFURL),
              let bsdName = DADiskGetBSDName(disk)
        else { return nil }

        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        // We search up the tree - IOMedia sits a few levels below the USB entry.
        let property = IORegistryEntrySearchCFProperty(
            service,
            kIOServicePlane,
            "USB Serial Number" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        )
        return property as? String
    }

    // MARK: - Files on the device

    /// `SysInfoExtended` is a plist with the `FireWireGUID` key.
    static func fromSysInfoExtended(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else { return nil }
        for key in ["FireWireGUID", "FirewireGuid", "SerialNumber"] {
            if let value = dictionary[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// `SysInfo` is plain text with lines like `FirewireGuid: 0x000A270012345678`.
    static func fromSysInfo(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            if parts[0].caseInsensitiveCompare("FirewireGuid") == .orderedSame { return parts[1] }
        }
        return nil
    }
}
