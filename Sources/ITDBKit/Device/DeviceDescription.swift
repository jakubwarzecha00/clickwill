import Foundation
import IOKit
import IOKit.scsi
import DiskArbitration

/// The device description given by the **iPod firmware** - the same plist that
/// iTunes used to store as `SysInfoExtended`. The most authoritative source: files on
/// disk are sometimes empty (a Classic and a nano 2G in testing had an empty `SysInfo`),
/// the macOS registry holds keys that are not the GUID, and here the device speaks for itself.
///
/// Reading: SCSI INQUIRY with VPD pages through the iPod driver in macOS
/// (`com_apple_driver_iPodSBCNub`, category `iPodUserClientDevice`). Page
/// 0xC0 lists the data pages, and those carry consecutive pieces of XML. Measured
/// on a nano 2G: without root, with the disk mounted, 26 pages, 6281 B.
/// INQUIRY changes nothing on the device.
public struct DeviceDescription: Sendable {

    /// An image format from the `AlbumArt` / `ImageSpecifications` list.
    public struct ImageFormat: Sendable, Hashable {
        public let formatID: UInt32
        public let width: Int
        public let height: Int
        /// Four-character code, e.g. `L565` (RGB565 little-endian) or `B565`.
        public let pixelFormat: String

        /// The only encoding we can write.
        public var isLittleEndianRGB565: Bool { pixelFormat == "L565" }
    }

    public let xml: Data
    public let serialNumber: String?
    public let fireWireGUID: String?
    public let familyID: Int?
    public let updaterFamilyID: Int?
    public let firmwareVersion: String?
    public let modelNumber: String?
    /// Artwork formats in which the device wants thumbnails.
    public let albumArt: [ImageFormat]

    // MARK: - Reading the file

    /// Apple's parser, not a strict one: the nano 2G firmware puts a `<key>` inside
    /// an `<array>`, which Python does not accept, but CoreFoundation does.
    public static func parse(xml: Data) throws -> DeviceDescription {
        guard let root = try PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else {
            throw ITDBError.pathMissing(URL(fileURLWithPath: "SysInfoExtended"))
        }
        func string(_ key: String) -> String? {
            (root[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func formats(_ key: String) -> [ImageFormat] {
            (root[key] as? [Any] ?? []).compactMap { item in
                guard let entry = item as? [String: Any],
                      let id = (entry["FormatId"] as? NSNumber)?.uint32Value,
                      let width = (entry["RenderWidth"] as? NSNumber)?.intValue,
                      let height = (entry["RenderHeight"] as? NSNumber)?.intValue
                else { return nil }
                return ImageFormat(formatID: id, width: width, height: height,
                                   pixelFormat: fourCharacterCode(entry["PixelFormat"] as? String))
            }
        }
        return DeviceDescription(
            xml: xml,
            serialNumber: string("SerialNumber"),
            fireWireGUID: string("FireWireGUID")?.uppercased(),
            familyID: (root["FamilyID"] as? NSNumber)?.intValue,
            updaterFamilyID: (root["UpdaterFamilyID"] as? NSNumber)?.intValue,
            firmwareVersion: string("VisibleBuildID"),
            modelNumber: string("ModelNumStr"),
            albumArt: formats("AlbumArt"))
    }

    /// `4C353635` -> `L565`. An invalid value stays as it was.
    static func fourCharacterCode(_ hex: String?) -> String {
        guard let hex, hex.count == 8, let value = UInt32(hex, radix: 16) else { return hex ?? "" }
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return hex }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Reading from the device

    /// Description of the iPod mounted at `mountPoint`; `nil` when not possible (no
    /// iPod driver, access denied, a disk image instead of an iPod).
    public static func read(mountPoint: URL) -> DeviceDescription? {
        guard let wholeDisk = wholeDiskName(of: mountPoint),
              let xml = SCSIInquiry.readDescription(bsdName: wholeDisk) else { return nil }
        return try? parse(xml: xml)
    }

    static func wholeDiskName(of mountPoint: URL) -> String? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, mountPoint as CFURL),
              let whole = DADiskCopyWholeDisk(disk),
              let name = DADiskGetBSDName(whole)
        else { return nil }
        return String(cString: name)
    }
}

/// SCSI channel to the iPod firmware. INQUIRY only.
enum SCSIInquiry {
    private static func uuid(_ b: [UInt8]) -> CFUUID {
        CFUUIDGetConstantUUIDWithBytes(nil, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }
    // Values from SCSITaskLib.h / IOCFPlugIn.h - macros Swift does not import.
    private static var userClientType: CFUUID { uuid([0x7D, 0x66, 0x67, 0x8E, 0x08, 0xA2, 0x11, 0xD5, 0xA1, 0xB8, 0x00, 0x30, 0x65, 0x7D, 0x05, 0x2A]) }
    private static var deviceInterface: CFUUID { uuid([0x1B, 0xBC, 0x41, 0x32, 0x08, 0xA5, 0x11, 0xD5, 0x90, 0xED, 0x00, 0x30, 0x65, 0x7D, 0x05, 0x2A]) }
    private static var plugInInterface: CFUUID { uuid([0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F]) }

    static func readDescription(bsdName: String) -> Data? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("com_apple_driver_iPodSBCNub"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let name = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "BSD Name" as CFString, nil,
                                                       IOOptionBits(kIORegistryIterateRecursively)) as? String
            guard name == bsdName else { continue }
            return inquire(service)
        }
        return nil
    }

    private static func inquire(_ service: io_service_t) -> Data? {
        var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, userClientType, plugInInterface, &plugin, &score) == KERN_SUCCESS,
              let plugin, let pluginTable = plugin.pointee?.pointee else { return nil }
        defer { _ = pluginTable.Release(plugin) }

        var raw: LPVOID?
        guard pluginTable.QueryInterface(plugin, CFUUIDGetUUIDBytes(deviceInterface), &raw) == 0, let raw else { return nil }
        let device = raw.assumingMemoryBound(to: UnsafeMutablePointer<SCSITaskDeviceInterface>.self)
        let deviceTable = device.pointee.pointee
        defer { _ = deviceTable.Release(device) }

        guard deviceTable.ObtainExclusiveAccess(device) == kIOReturnSuccess else { return nil }
        defer { _ = deviceTable.ReleaseExclusiveAccess(device) }
        guard let task = deviceTable.CreateSCSITask(device), let taskTable = task.pointee?.pointee else { return nil }
        defer { _ = taskTable.Release(task) }

        func page(_ number: UInt8) -> [UInt8]? {
            var buffer = [UInt8](repeating: 0, count: 255)
            var sense = SCSI_Sense_Data()
            var status = SCSITaskStatus(0)
            var realized: UInt64 = 0
            _ = taskTable.ResetForNewTask(task)
            var cdb: [UInt8] = [0x12, 0x01, number, 0x00, 0xFF, 0x00]   // INQUIRY, EVPD
            let result: IOReturn = buffer.withUnsafeMutableBytes { bytes in
                var range = IOVirtualRange(address: IOVirtualAddress(UInt(bitPattern: bytes.baseAddress)),
                                           length: IOByteCount(bytes.count))
                _ = taskTable.SetCommandDescriptorBlock(task, &cdb, UInt8(cdb.count))
                _ = taskTable.SetScatterGatherEntries(task, &range, 1, UInt64(bytes.count),
                                                      UInt8(kSCSIDataTransfer_FromTargetToInitiator))
                _ = taskTable.SetTimeoutDuration(task, 5000)
                return taskTable.ExecuteTaskSync(task, &sense, &status, &realized)
            }
            guard result == kIOReturnSuccess, status == kSCSITaskStatus_GOOD, realized >= 4 else { return nil }
            return Array(buffer[4..<min(4 + Int(buffer[3]), Int(realized))])
        }

        guard let index = page(0xC0), !index.isEmpty else { return nil }
        var xml: [UInt8] = []
        for number in index {
            guard let part = page(number) else { return nil }
            xml += part
        }
        return Data(xml)
    }
}
