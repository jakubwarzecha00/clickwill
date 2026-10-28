import Foundation
import IOKit
import DiskArbitration

/// Who the iPod presents itself as on USB - a second source, independent of the database,
/// of which signature to expect.
///
/// Why a second source: the scheme is read from field 0x30 of the database, and the database may have come
/// from another device (a copy put there by hand, a restore from someone else's backup).
/// The USB product identifier comes from the firmware - it cannot be replaced
/// with a file. When the two sources disagree, writing is blocked, not
/// settled in favor of either of them.
///
/// Without the USB registry (a disk image instead of an iPod) `read` gives `nil` and the
/// database alone decides.
public struct USBIdentity: Sendable, Hashable {
    /// Apple.
    public static let appleVendorID: UInt16 = 0x05AC
    /// iPod classic (6G, 6.5G, 7G) in disk mode.
    public static let classicProductID: UInt16 = 0x1261

    public let productID: UInt16

    public init(productID: UInt16) {
        self.productID = productID
    }

    /// Disk mode identifiers and the schemes that belong to them. Source:
    /// the public USB ID list `usb.ids` (linux-usb.org), schemes
    /// according to libgpod. An identifier outside the table means "no opinion", not "agreement".
    static let families: [UInt16: (name: String, scheme: UInt16)] = [
        // Before 2007: unsigned.
        0x1201: ("iPod (3rd generation)", 0),
        0x1202: ("iPod (1st/2nd generation)", 0),
        0x1203: ("iPod (4th generation)", 0),
        0x1204: ("iPod photo", 0),
        0x1205: ("iPod mini", 0),
        0x1209: ("iPod (5th generation)", 0),
        0x120A: ("iPod nano (1st generation)", 0),
        0x1260: ("iPod nano (2nd generation)", 0),
        // hash58.
        0x1261: ("iPod classic", 1),
        0x1262: ("iPod nano (3rd generation)", 1),
        0x1263: ("iPod nano (4th generation)", 1),
        // hash72 and hashAB.
        0x1265: ("iPod nano (5th generation)", 2),
        0x1266: ("iPod nano (6th generation)", 4),
        0x1267: ("iPod nano (7th generation)", 4),
    ]

    /// The family name, when the identifier is in the table.
    public var familyName: String? { Self.families[productID]?.name }

    /// The signing scheme this family uses.
    public var expectedScheme: UInt16? { Self.families[productID]?.scheme }

    /// A mismatch with the database - or `nil` when they agree or when
    /// we do not know the identifier.
    public func conflict(withDatabaseScheme scheme: UInt16) -> IdentityConflict? {
        guard let expected = expectedScheme, let name = familyName, expected != scheme else { return nil }
        return .usbScheme(family: name, expected: expected, database: scheme)
    }

    // MARK: - Reading

    /// Volume -> BSD device -> up the IORegistry tree to the USB entry.
    public static func read(mountPoint: URL) -> USBIdentity? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, mountPoint as CFURL),
              let bsdName = DADiskGetBSDName(disk),
              let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> UInt16? {
            let value = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively))
            return (value as? NSNumber).map { UInt16(truncatingIfNeeded: $0.intValue) }
        }
        guard number("idVendor") == appleVendorID, let product = number("idProduct") else { return nil }
        return USBIdentity(productID: product)
    }
}
