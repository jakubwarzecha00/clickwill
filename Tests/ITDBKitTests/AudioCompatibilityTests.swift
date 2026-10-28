import Testing
@testable import ITDBKit

private func stream(_ id: String, bits: Int = 0, rate: Int = 44_100, ch: Int = 2, bitRate: Int = 0, ext: String) -> AudioStream {
    AudioStream(formatID: id, bitsPerChannel: bits, sampleRate: rate, channels: ch, bitRate: bitRate, fileExtension: ext)
}

@Suite("Format compatibility with the iPod Classic")
struct AudioCompatibilityTests {

    @Test("formats the iPod plays")
    func supported() {
        #expect(AudioCompatibility.verdict(for: stream(".mp3", rate: 44_100, bitRate: 320_000, ext: "mp3")).isSupported)
        #expect(AudioCompatibility.verdict(for: stream(".mp3", rate: 48_000, bitRate: 192_000, ext: "mp3")).isSupported)
        #expect(AudioCompatibility.verdict(for: stream("aac ", rate: 44_100, bitRate: 256_000, ext: "m4a")).isSupported)
        #expect(AudioCompatibility.verdict(for: stream("alac", bits: 16, rate: 48_000, ext: "m4a")).isSupported)
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 16, rate: 44_100, ext: "wav")).isSupported)
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 16, rate: 44_100, ext: "wav")).isSupported)
        // The iPod plays AIFF, but its description in the database is not measured - an added one goes as ALAC.
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 16, rate: 44_100, ext: "aiff"))
                == .convertible(reason: "AIFF is stored as Apple Lossless: every sample kept, in a smaller file",
                                target: .appleLossless(sampleRate: 44_100)))
    }

    @Test("AIFF already on the iPod: it plays if within the limits - no badge and no conversion")
    func aiffOnDevice() {
        // The Classic plays 16-bit AIFF from a CD import (The ultimate sin, checked on the device).
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 16, rate: 44_100, ext: "aiff"), purpose: .playing) == .supported)
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 16, rate: 44_100, ext: "aif"), purpose: .playing) == .supported)
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 24, rate: 44_100, ext: "aiff"), purpose: .playing)
                == .convertible(reason: "24-bit AIFF; the iPod plays 16-bit up to 48 kHz", target: .appleLossless(sampleRate: 44_100)))
        // The other formats are judged the same way in both cases.
        #expect(AudioCompatibility.verdict(for: stream("lpcm", bits: 16, rate: 44_100, ext: "wav"), purpose: .playing) == .supported)
        #expect(!AudioCompatibility.verdict(for: stream("flac", bits: 16, rate: 44_100, ext: "flac"), purpose: .playing).isSupported)
    }

    @Test("24 bits: conversion to 16-bit ALAC keeping the sample rate")
    func deepBits() throws {
        // Exactly the cases from a real device.
        let alac = AudioCompatibility.verdict(for: stream("alac", bits: 24, rate: 48_000, ext: "m4a"))
        guard case .convertible(let reason, let target) = alac else { Issue.record("a conversion was expected"); return }
        #expect(reason.contains("24-bit"))
        #expect(target == .appleLossless(sampleRate: 48_000))
        let wav = AudioCompatibility.verdict(for: stream("lpcm", bits: 24, rate: 44_100, ext: "wav"))
        #expect(wav == .convertible(reason: "24-bit WAV; the iPod plays 16-bit up to 48 kHz", target: .appleLossless(sampleRate: 44_100)))
    }

    @Test("over 48 kHz goes down to 48 kHz; FLAC and friends go to ALAC")
    func highRatesAndForeignFormats() {
        #expect(AudioCompatibility.verdict(for: stream("alac", bits: 16, rate: 96_000, ext: "m4a"))
                == .convertible(reason: "Apple Lossless at 96 kHz; the iPod plays 16-bit up to 48 kHz", target: .appleLossless(sampleRate: 48_000)))
        guard case .convertible(let reason, let target) = AudioCompatibility.verdict(for: stream("flac", bits: 24, rate: 96_000, ext: "flac")) else {
            Issue.record("FLAC should be convertible"); return
        }
        #expect(reason.contains("FLAC"))
        #expect(target == .appleLossless(sampleRate: 48_000))
    }

    @Test("rejections: multichannel and an unknown codec")
    func rejected() {
        #expect(AudioCompatibility.verdict(for: stream("alac", bits: 16, rate: 48_000, ch: 6, ext: "m4a"))
                == .rejected(reason: "6 channels; the iPod plays mono and stereo only"))
        if case .rejected(let reason) = AudioCompatibility.verdict(for: stream("zzzz", ext: "bin")) {
            #expect(reason.contains("zzzz"))
        } else { Issue.record("an unknown codec should be rejected") }
    }

    @Test("labels for the interface")
    func labels() {
        #expect(AudioCompatibility.label(for: stream("alac", bits: 24, rate: 48_000, ext: "m4a")) == "ALAC 24-bit 48 kHz")
        #expect(AudioCompatibility.label(for: stream(".mp3", rate: 44_100, bitRate: 320_000, ext: "mp3")) == "MP3 44.1 kHz 320 kbps")
    }
}
