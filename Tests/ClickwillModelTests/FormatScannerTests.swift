import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The file format scan without the model - on a fake iPod with one
/// WAV 24 bit / 96 kHz file (track 14); the other files are not audio.
@Suite("Format scan")
@MainActor
struct FormatScannerTests {

    private func scanner(_ rig: WriteTests.Rig, batchSize: Int = 50) throws -> (FormatScanner, [ITTrack]) {
        let session = try LibrarySession.open(try #require(rig.model.source))
        var scanner = FormatScanner(paths: session.paths, capabilities: session.capabilities)
        scanner.batchSize = batchSize
        return (scanner, session.library.tracks)
    }

    /// A scan of the list in library order, without an album on screen.
    private func scanAll(_ scanner: FormatScanner, _ tracks: [ITTrack], isCurrent: () -> Bool = { true },
                         deliver: (FormatReport) -> Void) async -> Bool {
        var queue = FormatScanQueue(tracks)
        return await scanner.scan(next: { queue.next() }, isCurrent: isCurrent, deliver: deliver)
    }

    @Test("a 24/96 file to convert, unreadable files without a verdict")
    func verdicts() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let (scanner, tracks) = try scanner(rig)
        var report = FormatReport()
        let finished = await scanAll(scanner, tracks) { report.merge($0) }

        #expect(finished)
        #expect(Set(report.verdicts.keys) == [14])
        guard case .convertible = try #require(report.verdicts[14]) else { Issue.record("\(report.verdicts)"); return }
        #expect(report.labels[14]?.contains("24") == true)
    }

    /// A file on the iPod is judged by whether the iPod plays it. The Classic plays 16 bit /
    /// 44.1 kHz AIFF from a CD import - the badge "the iPod skips it" next to
    /// it was untrue (a record described as ALAC changes nothing here).
    @Test("16/44.1 AIFF lying on the iPod: it plays, no conversion verdict")
    func aiffOnDevicePlays() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let (scanner, tracks) = try scanner(rig)
        let relative = "iPod_Control/Music/F00/CD01.aiff"
        try AudioCDTests.writeSilence(to: rig.paths.mountPoint.appendingPathComponent(relative), seconds: 1)
        let aiff = tracks[0].replacingFile(relativePath: relative, sizeBytes: 1, bitRate: 0, sampleRate: 44_100, kind: .appleLossless)
        var report = FormatReport()
        _ = await scanAll(scanner, [aiff]) { report.merge($0) }
        #expect(report.verdicts[aiff.uniqueID] == .supported)
        #expect(report.labels[aiff.uniqueID]?.contains("16") == true)
    }

    /// A new scan reads from the same queue: a track taken by a scan that
    /// is just stopping would not be checked by anyone.
    @Test("a stopped scan does not take a track from the queue")
    func interruptedLeavesTrack() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let (scanner, tracks) = try scanner(rig)
        var queue = FormatScanQueue(tracks)
        var asked = 0
        _ = await scanner.scan(next: { queue.next() }, isCurrent: { asked += 1; return asked < 2 }) { _ in }
        #expect(queue.next()?.uniqueID == tracks[1].uniqueID, "the first checked, the second waits in the queue")
    }

    @Test("batches of batchSize, the last batch handed over at the end")
    func batches() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let (scanner, tracks) = try scanner(rig, batchSize: 1)
        var sizes: [Int] = []
        _ = await scanAll(scanner, tracks) { sizes.append($0.verdicts.count) }
        #expect(sizes == [1, 0])
    }

    @Test("a stopped scan hands over nothing and says it did not finish")
    func interrupted() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let (scanner, tracks) = try scanner(rig)
        var asked = 0
        var delivered = 0
        let finished = await scanAll(scanner, tracks, isCurrent: { asked += 1; return asked < 3 }) { _ in delivered += 1 }
        #expect(!finished)
        #expect(delivered == 0)
        #expect(asked == 3, "a question before each file, the end at the first false")
    }

    /// A bug from released versions: the view started the scan in `.task(id: generation)`
    /// with the condition `state == .loaded`, and the load number grows before the state
    /// reaches `.loaded` - the task exited without a scan and the
    /// "the iPod skips it" badges never appeared.
    @Test("after loading the model scans formats by itself; the verdict reaches the track list")
    func scanStartsAfterLoad() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        let scan = try #require(rig.model.formatScan, "loading starts the scan")
        await scan.value
        #expect(rig.model.formatScanComplete)
        let row = try #require(rig.model.albums.flatMap { rig.model.tracks(of: $0) }.first { $0.id == 14 })
        #expect(row.unplayable)
    }
}
