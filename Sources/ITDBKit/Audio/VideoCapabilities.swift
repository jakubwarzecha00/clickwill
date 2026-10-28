import Foundation

/// Video limits of a specific iPod model. `nil` in `IPodCapabilities.video`
/// means: this iPod does not play video and the option must be hidden.
///
/// **Where the numbers come from: Apple's technical specifications, not measurement.**
/// There is no video file on a test device yet - so this is knowledge
/// "from the format", to be confirmed by the first video the iPod
/// actually plays.
public struct VideoCapabilities: Sendable, Hashable {
    public let maximumWidth: Int
    public let maximumHeight: Int
    /// H.264 Baseline profile - these iPods decode no other profiles.
    public let maximumH264BitRate: Int
    /// Highest H.264 level for the given resolution.
    public let h264Level: String
    public let maximumMPEG4BitRate: Int
    /// Audio: AAC-LC, at most 48 kHz, stereo.
    public let maximumAudioBitRate: Int

    /// iPod classic 6G/7G and nano 3G/4G: up to 640x480, H.264 Baseline
    /// Low-Complexity up to 1.5 Mb/s, MPEG-4 Simple Profile up to 2.5 Mb/s.
    public static let vga = VideoCapabilities(
        maximumWidth: 640, maximumHeight: 480, maximumH264BitRate: 1_500_000, h264Level: "3.0",
        maximumMPEG4BitRate: 2_500_000, maximumAudioBitRate: 160_000)

    /// iPod 5G (video): a safe common denominator of 5G and 5.5G - 320x240,
    /// H.264 Baseline up to 768 kb/s at level 1.3.
    public static let qvga = VideoCapabilities(
        maximumWidth: 320, maximumHeight: 240, maximumH264BitRate: 768_000, h264Level: "1.3",
        maximumMPEG4BitRate: 2_500_000, maximumAudioBitRate: 160_000)

    public var label: String { "\(maximumWidth)×\(maximumHeight), H.264 Baseline" }
}

extension IPodCapabilities {
    /// Model numbers from before 2007 that play video. A closed list:
    /// an unrecognized older iPod gets **no video**, because a file the iPod
    /// will not play is worse than a missing option.
    static let videoModelsBefore2007: [String: VideoCapabilities] = [
        "A1136": .qvga,   // iPod (5th generation) / 5.5G
    ]

    /// Profile derived from the database format and the model number.
    ///
    /// The format settles the generation: every device with a hash58 signature is a
    /// 2007 model or newer - Classic 6G/7G or nano 3G/4G - and every one of them
    /// plays video. For older ones only the model number decides: the nano 2G
    /// (A1199) does not play video, the iPod 5G (A1136) does.
    public static func resolve(format: DatabaseFormat, model: IPodModel) -> IPodCapabilities {
        var profile = resolve(hashingScheme: format.signing == .hash58 ? Hash58.schemeIdentifier : 0)
        switch format.signing {
        case .hash58:
            profile.video = .vga
        case .presumedUnsigned, .unknown:
            profile.video = model.modelNumber.flatMap { videoModelsBefore2007[$0.uppercased()] }
        }
        return profile
    }

    public var supportsVideo: Bool { video != nil }
}
