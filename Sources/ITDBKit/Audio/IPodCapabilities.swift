import Foundation

/// Audio format limits of a specific iPod model.
///
/// `AudioCompatibility` used to know only one set of numbers - the one
/// measured on the Classic 7G. For older devices some of them are wrong:
/// the iPod 1G and 2G and both early shuffles do not know Apple Lossless, so
/// "convert to the highest supported format" means something else there.
/// The profile is a value so that there is one rule and the numbers come from the model.
public struct IPodCapabilities: Sendable, Hashable {
    /// Name for the interface - it appears in the sentence "the iPod plays...".
    public let name: String
    public let maximumSampleRate: Int
    /// Highest bit depth of lossless formats.
    public let maximumBitDepth: Int
    public let maximumChannels: Int
    public let maximumMP3BitRate: Int
    /// Apple Lossless arrived with the iPod 3G; earlier models and the shuffle do not play it.
    public let supportsAppleLossless: Bool
    /// AAC bitrate we encode to when lossless is not possible.
    public let aacBitRate: Int
    /// Whether the profile was recognized or only assumed. The interface must say
    /// so plainly - silently guessing the limits would be worse than having none.
    public var isAssumed: Bool
    /// Video limits; `nil` when this iPod does not play video.
    public var video: VideoCapabilities? = nil

    public init(name: String, maximumSampleRate: Int, maximumBitDepth: Int, maximumChannels: Int,
                maximumMP3BitRate: Int, supportsAppleLossless: Bool, aacBitRate: Int, isAssumed: Bool = false) {
        self.name = name
        self.maximumSampleRate = maximumSampleRate
        self.maximumBitDepth = maximumBitDepth
        self.maximumChannels = maximumChannels
        self.maximumMP3BitRate = maximumMP3BitRate
        self.supportsAppleLossless = supportsAppleLossless
        self.aacBitRate = aacBitRate
        self.isAssumed = isAssumed
    }

    /// Touch-wheel iPods from the 5G on - Classic 6G and 7G, nano 3G and later.
    /// The only profile confirmed on hardware: an album in 24-bit ALAC had zero
    /// plays since March 2025, against 879 plays in the rest of the library.
    public static let classic = IPodCapabilities(
        name: "iPod classic", maximumSampleRate: 48_000, maximumBitDepth: 16, maximumChannels: 2,
        maximumMP3BitRate: 320_000, supportsAppleLossless: true, aacBitRate: 256_000)

    /// iPod 3G, 4G, mini, photo, nano 1G and 2G. Apple Lossless is already there.
    public static let clickWheel = IPodCapabilities(
        name: "iPod (click wheel)", maximumSampleRate: 48_000, maximumBitDepth: 16, maximumChannels: 2,
        maximumMP3BitRate: 320_000, supportsAppleLossless: true, aacBitRate: 256_000)

    /// iPod 1G and 2G - with a scroll wheel, before Apple Lossless.
    public static let scrollWheel = IPodCapabilities(
        name: "iPod (scroll wheel)", maximumSampleRate: 48_000, maximumBitDepth: 16, maximumChannels: 2,
        maximumMP3BitRate: 320_000, supportsAppleLossless: false, aacBitRate: 256_000)

    /// iPod shuffle - no screen and no Apple Lossless.
    public static let shuffle = IPodCapabilities(
        name: "iPod shuffle", maximumSampleRate: 48_000, maximumBitDepth: 16, maximumChannels: 2,
        maximumMP3BitRate: 320_000, supportsAppleLossless: false, aacBitRate: 256_000)

    public static let all: [IPodCapabilities] = [classic, clickWheel, scrollWheel, shuffle]

    /// Target format for a lossless source: ALAC where the device knows
    /// it, AAC where it does not. The rule stays the same - the highest supported.
    public func losslessTarget(sampleRate: Int) -> AudioCompatibility.Target {
        guard supportsAppleLossless else { return .aac(bitRate: aacBitRate) }
        return .appleLossless(sampleRate: min(sampleRate, maximumSampleRate))
    }

    /// Device profile derived from what we actually read.
    ///
    /// The only reliable signal we have without `SysInfoExtended` is the database
    /// signing scheme: hash58 arrived only with the 2007 models, i.e. Classic 6G/7G
    /// and nano 3G and later - and those have the full set. An older device cannot
    /// be told apart from the database alone, so we assume the touch-wheel profile
    /// and mark it as an assumption instead of pretending to recognize it.
    public static func resolve(hashingScheme: UInt16) -> IPodCapabilities {
        guard hashingScheme == Hash58.schemeIdentifier else {
            var assumed = clickWheel
            assumed.isAssumed = true
            return assumed
        }
        return classic
    }

    /// The profile for each USB family (`USBIdentity.families`). The USB identifier comes
    /// from the firmware, so it names the model without guessing from the database.
    static let byUSBProduct: [UInt16: IPodCapabilities] = [
        0x1202: scrollWheel,
        0x1201: clickWheel, 0x1203: clickWheel, 0x1204: clickWheel, 0x1205: clickWheel,
        0x120A: clickWheel, 0x1260: clickWheel,
        0x1209: classic, 0x1261: classic, 0x1262: classic, 0x1263: classic,
    ]

    /// The profile of a connected iPod: from its USB family when the family is known -
    /// named after the model and not assumed - otherwise from the database and model
    /// number (`resolve(format:model:)`). Video limits always come from the latter.
    public static func resolve(for device: IPodDevice) -> IPodCapabilities {
        let fromDatabase = resolve(format: device.format, model: device.model)
        guard let usb = device.usb, let known = byUSBProduct[usb.productID], let name = usb.familyName else {
            return fromDatabase
        }
        var profile = known.named(name)
        profile.video = fromDatabase.video
        return profile
    }

    /// The same limits under another name.
    func named(_ name: String) -> IPodCapabilities {
        var copy = IPodCapabilities(name: name, maximumSampleRate: maximumSampleRate, maximumBitDepth: maximumBitDepth,
                                    maximumChannels: maximumChannels, maximumMP3BitRate: maximumMP3BitRate,
                                    supportsAppleLossless: supportsAppleLossless, aacBitRate: aacBitRate, isAssumed: isAssumed)
        copy.video = video
        return copy
    }
}
