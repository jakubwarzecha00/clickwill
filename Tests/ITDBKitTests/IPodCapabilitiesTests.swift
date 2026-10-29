import Testing
import Foundation
@testable import ITDBKit

/// Format limits depend on the model. They used to be constant and taken
/// from the Classic - these tests make sure the profile actually changes the verdict,
/// instead of just lying next to it.
@Suite("Device profiles")
struct IPodCapabilitiesTests {

    private func stream(_ id: String, bits: Int = 0, rate: Int = 44_100, ch: Int = 2,
                        bitRate: Int = 0, ext: String) -> AudioStream {
        AudioStream(formatID: id, bitsPerChannel: bits, sampleRate: rate, channels: ch,
                    bitRate: bitRate, fileExtension: ext)
    }

    @Test("ALAC plays on the Classic, does not play on an iPod with a scroll wheel")
    func losslessDependsOnModel() {
        let file = stream("alac", bits: 16, rate: 44_100, ext: "m4a")
        #expect(AudioCompatibility.verdict(for: file, on: .classic).isSupported)

        guard case .convertible(let reason, let target) = AudioCompatibility.verdict(for: file, on: .scrollWheel) else {
            Issue.record("the iPod 1G/2G does not know Apple Lossless - the file should go through conversion")
            return
        }
        #expect(reason.contains("Apple Lossless"))
        #expect(target == .aac(bitRate: 256_000))
    }

    @Test("FLAC: to ALAC on the Classic, to AAC on the shuffle")
    func flacTargetFollowsModel() {
        let file = stream("zzzz", rate: 44_100, ext: "flac")
        guard case .convertible(_, let onClassic) = AudioCompatibility.verdict(for: file, on: .classic),
              case .convertible(_, let onShuffle) = AudioCompatibility.verdict(for: file, on: .shuffle)
        else {
            Issue.record("FLAC always goes through conversion")
            return
        }
        #expect(onClassic == .appleLossless(sampleRate: 44_100))
        #expect(onShuffle == .aac(bitRate: 256_000))
    }

    @Test("24 bits drop out on every model, but the target is different")
    func bitDepthLimit() {
        let file = stream("lpcm", bits: 24, rate: 44_100, ext: "wav")
        guard case .convertible(_, let onClassic) = AudioCompatibility.verdict(for: file, on: .classic),
              case .convertible(_, let onScroll) = AudioCompatibility.verdict(for: file, on: .scrollWheel)
        else {
            Issue.record("a 24-bit WAV plays nowhere")
            return
        }
        #expect(onClassic == .appleLossless(sampleRate: 44_100))
        #expect(onScroll == .aac(bitRate: 256_000))
    }

    @Test("the profile from the database: hash58 means Classic, its absence - an assumption")
    func resolution() {
        let modern = IPodCapabilities.resolve(hashingScheme: Hash58.schemeIdentifier)
        #expect(modern.supportsAppleLossless)
        #expect(modern.isAssumed == false)

        let older = IPodCapabilities.resolve(hashingScheme: 0)
        #expect(older.isAssumed, "an unrecognized model must not be presented as recognized")
    }

    @Test("the default profile does not change the existing verdicts")
    func defaultUnchanged() {
        #expect(AudioCompatibility.verdict(for: stream(".mp3", rate: 44_100, bitRate: 320_000, ext: "mp3")).isSupported)
        #expect(AudioCompatibility.maximumBitDepth == 16)
        #expect(AudioCompatibility.maximumSampleRate == 48_000)
    }
}

/// Which iPods play video. The rule: a file the iPod will not play is worse
/// than a missing option - so an unrecognized older model does not get video.
@Suite("Video by model")
struct VideoCapabilityTests {

    private func format(_ signing: DatabaseFormat.Signing) -> DatabaseFormat {
        DatabaseFormat(headerLength: signing == .hash58 ? 244 : 0x68, version: 117, databaseID: 1, signing: signing)
    }
    private func model(_ number: String?) -> IPodModel {
        IPodModel(modelNumber: number, name: "x", source: number == nil ? .databaseOnly : .sysInfo)
    }

    @Test("every iPod with a hash58 signature plays 640x480 video")
    func modernPlaysVGA() {
        let profile = IPodCapabilities.resolve(format: format(.hash58), model: model(nil))
        #expect(profile.video == .vga)
        #expect(profile.video?.maximumWidth == 640)
    }

    @Test("the nano 2G (A1199) does not play video")
    func nano2GHasNoVideo() {
        // A device a user connects as a second one - the video option
        // must be invisible on it, not end with a file it will not play.
        let profile = IPodCapabilities.resolve(format: format(.presumedUnsigned), model: model("A1199"))
        #expect(profile.supportsVideo == false)
    }

    @Test("the iPod 5G plays video at a safe 320x240")
    func fifthGeneration() {
        let profile = IPodCapabilities.resolve(format: format(.presumedUnsigned), model: model("A1136"))
        #expect(profile.video == .qvga)
    }

    @Test("an older iPod without a model number does not get video")
    func unknownOldModelHasNoVideo() {
        #expect(IPodCapabilities.resolve(format: format(.presumedUnsigned), model: model(nil)).supportsVideo == false)
        #expect(IPodCapabilities.resolve(format: format(.unknown(3)), model: model(nil)).supportsVideo == false)
    }
}

@Suite("Profile from the USB family")
struct USBProfileTests {

    func device(_ usb: USBIdentity?, signing: DatabaseFormat.Signing) -> IPodDevice {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("profile-\(UUID().uuidString)")
        return IPodDevice(volume: IPodVolume(paths: IPodPaths(mountPoint: root), name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                          fireWireID: nil, format: DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: signing),
                          model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly), usb: usb)
    }

    @Test("the nano 2G is named and recognized from USB, not an assumed click-wheel iPod")
    func nanoFromUSB() {
        let profile = IPodCapabilities.resolve(for: device(USBIdentity(productID: 0x1260), signing: .presumedUnsigned))
        #expect(profile.name == "iPod nano (2nd generation)")
        #expect(!profile.isAssumed)
        #expect(profile.supportsAppleLossless)
        #expect(profile.video == nil)
    }

    @Test("the nano 3G gets the Classic limits under its own name, with video")
    func nano3FromUSB() {
        let profile = IPodCapabilities.resolve(for: device(USBIdentity(productID: 0x1262), signing: .hash58))
        #expect(profile.name == "iPod nano (3rd generation)")
        #expect(profile.maximumBitDepth == IPodCapabilities.classic.maximumBitDepth)
        #expect(profile.video == .vga)
    }

    @Test("without USB the database decides, as before")
    func withoutUSB() {
        #expect(IPodCapabilities.resolve(for: device(nil, signing: .presumedUnsigned)).isAssumed)
        #expect(IPodCapabilities.resolve(for: device(nil, signing: .hash58)) == IPodCapabilities.resolve(
            format: DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .hash58),
            model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly)))
    }
}
