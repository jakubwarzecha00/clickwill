import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The Mac's disk, which records which music files were asked about - the order
/// shows which tracks the scan checked first.
private final class RecordingFileSystem: FileSystem, @unchecked Sendable {
    let local = LocalFileSystem()
    var askedAudio: [String] = []
    /// Called on the first question about a music file - "the user opens an album during the scan".
    var onFirstAudio: (() -> Void)?

    func fileExists(at url: URL) -> Bool {
        if ["mp3", "wav"].contains(url.pathExtension) {
            askedAudio.append(url.deletingPathExtension().lastPathComponent)
            if askedAudio.count == 1 { onFirstAudio?() }
        }
        return local.fileExists(at: url)
    }
    func isDirectory(at url: URL) -> Bool { local.isDirectory(at: url) }
    func isRegularFile(at url: URL) -> Bool { local.isRegularFile(at: url) }
    func contents(of url: URL) throws -> Data { try local.contents(of: url) }
    func size(of url: URL) -> Int64? { local.size(of: url) }
    func removeItem(at url: URL) throws { try local.removeItem(at: url) }
    func createDirectory(at url: URL) throws { try local.createDirectory(at: url) }
    func symbolicLinkDestination(at url: URL) -> String? { local.symbolicLinkDestination(at: url) }
    func createSymbolicLink(at url: URL, to destination: URL) throws { try local.createSymbolicLink(at: url, to: destination) }
    var temporaryDirectory: URL { local.temporaryDirectory }
}

@Suite("Format scan order")
@MainActor
struct FormatScanQueueTests {

    /// The synthetic library: tracks 10-16 in three albums.
    private let tracks = try! ITunesDBParser.parse(SyntheticLibrary.database()).tracks

    private func drain(_ queue: inout FormatScanQueue) -> [UInt32] {
        var ids: [UInt32] = []
        while let track = queue.next() { ids.append(track.uniqueID) }
        return ids
    }

    @Test("no album on screen: library order, each track once")
    func libraryOrder() {
        var queue = FormatScanQueue(tracks)
        #expect(drain(&queue) == tracks.map(\.uniqueID))
    }

    @Test("an album on screen before the start: its tracks first, the rest without repeats")
    func albumFirst() {
        var queue = FormatScanQueue(tracks)
        queue.prioritize([16, 15])
        let order = drain(&queue)
        #expect(Array(order.prefix(2)) == [15, 16], "in library order")
        #expect(order.sorted() == tracks.map(\.uniqueID).sorted())
    }

    @Test("an album opened during the scan: it jumps the rest; checked tracks do not come back")
    func albumMidway() {
        var queue = FormatScanQueue(tracks)
        let first = [queue.next()!.uniqueID, queue.next()!.uniqueID]
        queue.prioritize([first[0], tracks.last!.uniqueID])
        #expect(queue.next()?.uniqueID == tracks.last!.uniqueID)
        let rest = drain(&queue)
        #expect((first + [tracks.last!.uniqueID] + rest).sorted() == tracks.map(\.uniqueID).sorted())
    }

    @Test("a new album on screen replaces the previous one")
    func latestAlbumWins() {
        var queue = FormatScanQueue(tracks)
        queue.prioritize([16])
        queue.prioritize([14])
        #expect(queue.next()?.uniqueID == 14)
        #expect(queue.next()?.uniqueID == tracks.first!.uniqueID)
    }

    @Test("model: an album opened right after loading is checked first")
    func modelChecksOpenAlbumFirst() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let files = RecordingFileSystem()
        var environment = rig.environment
        environment.files = files
        let model = LibraryModel(environment: environment)
        await model.load(try #require(rig.model.source))
        let album = try #require(model.albums.first { $0.title == "Currents" })
        let albumIDs = model.tracks(of: album).map { String($0.id) }
        #expect(albumIDs.count == 2)

        files.askedAudio = []
        model.prioritizeFormatCheck(of: album)
        await try #require(model.formatScan).value

        #expect(Array(files.askedAudio.prefix(albumIDs.count)) == albumIDs, "\(files.askedAudio)")
        #expect(Set(files.askedAudio).count == files.askedAudio.count, "each file once")
        #expect(model.formatScanComplete)
    }

    @Test("model: an album opened during the scan jumps the rest of the library")
    func modelChecksAlbumOpenedMidway() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let files = RecordingFileSystem()
        var environment = rig.environment
        environment.files = files
        let model = LibraryModel(environment: environment)
        await model.load(try #require(rig.model.source))
        let album = try #require(model.albums.first { $0.title == "Currents" })
        let albumIDs = model.tracks(of: album).map { String($0.id) }

        files.askedAudio = []
        files.onFirstAudio = { MainActor.assumeIsolated { model.prioritizeFormatCheck(of: album) } }
        await try #require(model.formatScan).value

        let first = try #require(files.askedAudio.first)
        #expect(!albumIDs.contains(first), "the first file checked before the album was opened")
        #expect(Array(files.askedAudio.dropFirst().prefix(albumIDs.count)) == albumIDs, "\(files.askedAudio)")
        #expect(Set(files.askedAudio).count == files.askedAudio.count, "each file once")
        #expect(model.formatScanComplete)
    }
}
