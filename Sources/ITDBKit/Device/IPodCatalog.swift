import Foundation

/// Generation and color of the iPod - for the drawing and the name on screen.
///
/// **No third-party tables**: the generation follows from what
/// the device says about itself - the USB family, the firmware version, the disk
/// capacity. We know the color only for serial number suffixes confirmed on
/// real units (`confirmedFinishes`); for the rest - the family's shape
/// in a neutral color.
///
/// **This is cosmetic, just like `IPodModel`.** From the catalog we take a picture
/// and a name, never a decision about writing.
public enum IPodCatalog {

    /// Generation - the shape of the case in the picture depends on it.
    public enum Generation: String, Sendable, CaseIterable {
        case firstSecond, third, fourth, photo, mini, video
        case classic1, classic2, classic3
        case nano1, nano2, nano3, nano4, nano5, nano6

        public var name: String {
            switch self {
            case .firstSecond: "iPod (1st or 2nd generation)"
            case .third: "iPod (3rd generation)"
            case .fourth: "iPod (4th generation)"
            case .photo: "iPod photo"
            case .mini: "iPod mini"
            case .video: "iPod (5th generation)"
            case .classic1: "iPod classic (2007)"
            case .classic2: "iPod classic (2008)"
            case .classic3: "iPod classic (2009)"
            case .nano1: "iPod nano (1st generation)"
            case .nano2: "iPod nano (2nd generation)"
            case .nano3: "iPod nano (3rd generation)"
            case .nano4: "iPod nano (4th generation)"
            case .nano5: "iPod nano (5th generation)"
            case .nano6: "iPod nano (6th generation)"
            }
        }

        /// Whether the iPod has Cover Flow: classic and nano from the 3rd to the 5th generation.
        /// The others show albums only as a list - the app then hides
        /// the Cover Flow tab.
        public var hasCoverFlow: Bool {
            switch self {
            case .classic1, .classic2, .classic3, .nano3, .nano4, .nano5: true
            default: false
            }
        }

        /// Short, for tight spots (the card in the sidebar): "iPod nano".
        public var familyName: String {
            switch self {
            case .classic1, .classic2, .classic3: "iPod classic"
            case .nano1, .nano2, .nano3, .nano4, .nano5, .nano6: "iPod nano"
            case .mini: "iPod mini"
            case .photo: "iPod photo"
            default: "iPod"
            }
        }
    }

    /// Case color. `u2` - a black case with a red wheel.
    public enum Finish: String, Sendable, CaseIterable {
        case white, black, silver, blue, pink, green, gold, red, orange, purple, yellow, u2

        public var name: String {
            switch self {
            case .u2: "U2 Special Edition"
            case .red: "(PRODUCT)RED"
            default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
            }
        }
    }

    public struct Entry: Sendable, Hashable {
        public let generation: Generation
        /// Only from a confirmed serial number suffix.
        public let finish: Finish?

        /// A color shared by the whole generation - iPods 1G-3G were white only.
        /// The other generations came in several colors, so without a confirmed suffix - none.
        public var finishOrDefault: Finish? {
            if let finish { return finish }
            switch generation {
            case .firstSecond, .third: return .white
            default: return nil
            }
        }

        /// "iPod classic (2009), Black" or just the generation.
        public var name: String { finish.map { "\(generation.name), \($0.name)" } ?? generation.name }
    }

    /// Serial number suffixes (the last three characters) confirmed on
    /// a real unit: the USB identifier of that family and the case color.
    /// We add only iPods someone has had in hand - with a note on the source.
    static let confirmedFinishes: [String: (usbProductID: UInt16, finish: Finish)] = [
        // Test unit, classic 7G - black, in a space grey shade (checked in hand).
        "9ZU": (0x1261, .black),
        // Test unit, nano 2G - silver (on a photo of the unit).
        "VQ5": (0x1260, .silver),
    ]

    /// Generation from USB, firmware and capacity; color from a confirmed suffix.
    /// `nil` when the device does not say enough (e.g. a classic 160 GB without a firmware version).
    /// The iPod 1G and 2G share one USB identifier - one `firstSecond` generation.
    public static func entry(serial: String?, usbProductID: UInt16?, firmwareVersion: String?, capacity: Int64) -> Entry? {
        guard let product = usbProductID,
              let generation = generation(usbProductID: product, firmwareVersion: firmwareVersion, capacity: capacity)
        else { return nil }
        var finish: Finish?
        if let serial = serial?.trimmingCharacters(in: .whitespaces), serial.count >= 3,
           let confirmed = confirmedFinishes[String(serial.suffix(3)).uppercased()],
           confirmed.usbProductID == product {
            finish = confirmed.finish
        }
        return Entry(generation: generation, finish: finish)
    }

    /// Family from the USB identifier (`USBIdentity.families`). Classic: 2007
    /// has firmware 1.x; 2008 and 2009 have 2.x and differ by disk (120 and 160 GB).
    static func generation(usbProductID: UInt16, firmwareVersion: String?, capacity: Int64) -> Generation? {
        switch usbProductID {
        case 0x1202: return .firstSecond
        case 0x1201: return .third
        case 0x1203: return .fourth
        case 0x1204: return .photo
        case 0x1205: return .mini
        case 0x1209: return .video
        case 0x120A: return .nano1
        case 0x1260: return .nano2
        case 0x1262: return .nano3
        case 0x1263: return .nano4
        case 0x1265: return .nano5
        case 0x1266: return .nano6
        case 0x1261:
            let major = firmwareVersion?.split(separator: ".").first.flatMap { Int($0) }
            let gigabytes = Double(capacity) / 1_000_000_000
            switch major {
            case 1?: return .classic1
            case 2?: return gigabytes > 140 ? .classic3 : .classic2
            default:
                // Without firmware: 80 GB is only 2007, 120 GB only 2008; 160 GB can be 2007 or 2009.
                if gigabytes > 0, gigabytes < 100 { return .classic1 }
                if gigabytes >= 100, gigabytes < 140 { return .classic2 }
                return nil
            }
        default: return nil
        }
    }
}

extension IPodDevice {
    /// Generation and color - from what the device says about itself.
    public var catalogEntry: IPodCatalog.Entry? {
        IPodCatalog.entry(serial: firmwareDescription?.serialNumber, usbProductID: usb?.productID,
                          firmwareVersion: firmwareDescription?.firmwareVersion, capacity: volume.totalCapacity)
    }
}
