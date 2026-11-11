import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// What each format in the add sheet does to each kind of file.
@Suite("Import format")
@MainActor
struct ImportFormatTests {

    private static let flacVerdict = AudioCompatibility.Verdict.convertible(
        reason: "FLAC is not a format the iPod can read", target: .appleLossless(sampleRate: 44_100))

    private func file(_ title: String = "Song", kind: TrackFileKind, sourceKind: TrackFileKind?, bitRate: UInt32 = 0,
                      verdict: AudioCompatibility.Verdict = .supported, album: String = "Loveless",
                      url: URL? = nil) -> AudioImport.Candidate {
        let draft = TrackDraft(title: title, artist: "A", albumArtist: "A", album: album, durationMilliseconds: 180_000,
                               sizeBytes: 1_000, bitRate: bitRate, kind: kind, relativePath: "")
        return AudioImport.Candidate(url: url ?? URL(fileURLWithPath: "/tmp/\(title).\(kind.fileExtension)"), draft: draft,
                                     verdict: verdict, formatLabel: "x", artwork: nil, sourceKind: sourceKind)
    }

    private var flac: AudioImport.Candidate { file(kind: .flac, sourceKind: .flac, verdict: Self.flacVerdict) }

    private func applied(_ format: ImportFormat, _ candidate: AudioImport.Candidate,
                         on device: IPodCapabilities = .classic) -> AudioImport.Candidate {
        format.applied(to: candidate, fileVerdict: candidate.verdict, on: device)
    }

    private func target(_ candidate: AudioImport.Candidate) -> AudioCompatibility.Target? {
        if case .convertible(_, let target) = candidate.verdict { return target }
        return nil
    }

    @Test("Automatic leaves the file's own verdict")
    func automatic() {
        let result = applied(.automatic, flac)
        #expect(target(result) == .appleLossless(sampleRate: 44_100))
        #expect(!result.mayBeSkipped)
    }

    @Test("Keep Original: FLAC and high-resolution ALAC and WAV stay as they are and may be skipped")
    func keptLossless() {
        let over = AudioCompatibility.Verdict.convertible(reason: "24-bit", target: .appleLossless(sampleRate: 48_000))
        for candidate in [flac, file(kind: .appleLossless, sourceKind: .appleLossless, verdict: over),
                          file(kind: .wav, sourceKind: .wav, verdict: over)] {
            let result = applied(.original, candidate)
            #expect(result.verdict.isSupported)
            #expect(result.mayBeSkipped)
            #expect(result.draft.kind == candidate.draft.kind)
        }
    }

    @Test("Keep Original: a playable file carries no warning")
    func keptPlayable() {
        let result = applied(.original, file(kind: .mp3, sourceKind: .mp3, bitRate: 320))
        #expect(result.verdict.isSupported)
        #expect(!result.mayBeSkipped)
    }

    @Test("Keep Original: formats without a measured description are still converted")
    func keptUnmeasured() {
        let ogg = file(kind: .appleLossless, sourceKind: nil, verdict: .convertible(reason: "OGG", target: .appleLossless(sampleRate: 44_100)))
        let heAAC = file(kind: .aac, sourceKind: .aac, verdict: .convertible(reason: "HE-AAC", target: .aac(bitRate: 256_000)))
        for candidate in [ogg, heAAC] {
            let result = applied(.original, candidate)
            #expect(!result.verdict.isSupported)
            #expect(!result.mayBeSkipped)
        }
    }

    @Test("A rejected file stays rejected under every format")
    func rejected() {
        let candidate = file(kind: .appleLossless, sourceKind: .appleLossless, verdict: .rejected(reason: "6 channels"))
        for format in ImportFormat.allCases { #expect(applied(format, candidate).isHopeless) }
    }

    @Test("Apple Lossless: lossless files are converted, lossy ones and ALAC within limits stay")
    func appleLossless() {
        #expect(target(applied(.appleLossless, file(kind: .wav, sourceKind: .wav))) == .appleLossless(sampleRate: 44_100))
        #expect(target(applied(.appleLossless, flac)) == .appleLossless(sampleRate: 44_100))
        #expect(applied(.appleLossless, file(kind: .mp3, sourceKind: .mp3, bitRate: 320)).verdict.isSupported)
        #expect(applied(.appleLossless, file(kind: .appleLossless, sourceKind: .appleLossless)).verdict.isSupported)
    }

    @Test("Apple Lossless on an iPod that does not play it falls back to AAC")
    func appleLosslessUnsupported() {
        #expect(target(applied(.appleLossless, flac, on: .scrollWheel)) == .aac(bitRate: 256_000))
    }

    @Test("AAC: lossless files and larger lossy files are converted; smaller or unknown lossy files stay")
    func aac() {
        #expect(target(applied(.aac128, flac)) == .aac(bitRate: 128_000))
        #expect(target(applied(.aac128, file(kind: .mp3, sourceKind: .mp3, bitRate: 320))) == .aac(bitRate: 128_000))
        #expect(target(applied(.aac256, file(kind: .appleLossless, sourceKind: .appleLossless))) == .aac(bitRate: 256_000))
        #expect(applied(.aac256, file(kind: .aac, sourceKind: .aac, bitRate: 256)).verdict.isSupported)
        #expect(applied(.aac128, file(kind: .mp3, sourceKind: .mp3, bitRate: 128)).verdict.isSupported)
        #expect(applied(.aac128, file(kind: .mp3, sourceKind: .mp3, bitRate: 0)).verdict.isSupported)
    }

    @Test("A format can be changed back in the session, and files added later get it too")
    func sessionChangesBack() {
        var session = ImportSession(existing: SongIndex())
        session.add([flac], problems: [])
        #expect(session.converting == 1)

        session.setFormat(.original)
        #expect(session.converting == 0)
        #expect(session.candidates[0].mayBeSkipped)

        session.setFormat(.aac128)
        #expect(target(session.candidates[0]) == .aac(bitRate: 128_000))
        #expect(!session.candidates[0].mayBeSkipped)

        session.setFormat(.automatic)
        #expect(target(session.candidates[0]) == .appleLossless(sampleRate: 44_100))

        session.setFormat(.original)
        session.add([file("Later", kind: .flac, sourceKind: .flac, verdict: Self.flacVerdict)], problems: [])
        #expect(session.candidates.filter(\.mayBeSkipped).count == 2)
    }

    @Test("Only files really going to the iPod count towards the warning")
    func warningCount() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        var session = ImportSession(existing: rig.model.songIndex())
        session.add([file("One", kind: .flac, sourceKind: .flac, verdict: Self.flacVerdict),
                     file("Two", kind: .flac, sourceKind: .flac, verdict: Self.flacVerdict)], problems: [])
        #expect(session.mayBeSkippedCount(in: rig.model) == 0)

        session.setFormat(.original)
        #expect(session.mayBeSkippedCount(in: rig.model) == 2)

        session.remove(session.candidates[0].id)
        #expect(session.mayBeSkippedCount(in: rig.model) == 1)
    }

    @Test("A kept FLAC: the file unchanged in Music, the entry described as FLAC, the database signed")
    func keptFLACIsWritten() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let source = rig.root.appendingPathComponent("tone.flac")
        try Data(repeating: 9, count: 4000).write(to: source)
        var session = ImportSession(existing: rig.model.songIndex())
        session.add([file("Tone", kind: .flac, sourceKind: .flac, verdict: Self.flacVerdict, url: source)], problems: [])
        session.setFormat(.original)
        #expect(session.commit(to: rig.model).refused.isEmpty)
        #expect(rig.model.changes.additions.first?.mayBeSkipped == true)

        let outcome = try await rig.model.apply()

        #expect(outcome.addedTracks == 1)
        #expect(outcome.additionProblems.isEmpty, "\(outcome.additionProblems)")
        let added = try #require(try rig.onDisk().tracks.first { $0.title == "Tone" })
        #expect(added.fileKind == .flac)
        #expect(added.rawHeader[MhitLayout.fileTypeCode] == TrackFileKind.flac.fourCharacterValue)
        let stored = try #require(added.fileURL(on: rig.paths))
        #expect(stored.pathExtension == "flac")
        #expect(try Data(contentsOf: stored) == Data(repeating: 9, count: 4000))
        #expect(try rig.signedWithDeviceKey())
    }

    @Test("A FLAC with a missing data rate gets the average from its size and length")
    func flacBitRate() {
        let silent = AudioStream(formatID: "flac", bitsPerChannel: 0, sampleRate: 44_100, channels: 2, bitRate: 0, fileExtension: "flac")
        #expect(AudioImport.bitRateInKilobits(silent, sizeBytes: 886_728, duration: 60) == 118)
        #expect(AudioImport.bitRateInKilobits(silent, sizeBytes: 886_728, duration: 0) == 0)
        let known = AudioStream(formatID: ".mp3", bitsPerChannel: 0, sampleRate: 44_100, channels: 2, bitRate: 320_000, fileExtension: "mp3")
        #expect(AudioImport.bitRateInKilobits(known, sizeBytes: 1, duration: 60) == 320)
    }
}
