import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The change queue: the rule for deleting files from the iPod (shared by the app window
/// and `ipodctl`) and a log that does not drift apart from the tasks.
@Suite("Change queue")
struct ChangeSetTests {

    /// A Music folder with the files `a.mp3`, `b.mp3`, a folder `F01.mp3`
    /// and a link `link.mp3` to `a.mp3`.
    private struct Disk {
        let root: URL
        let paths: IPodPaths

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-changes-\(UUID().uuidString)")
            paths = IPodPaths(mountPoint: root)
            let folder = paths.musicDirectory.appendingPathComponent("F00")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1]).write(to: folder.appendingPathComponent("a.mp3"))
            try Data([2]).write(to: folder.appendingPathComponent("b.mp3"))
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("F01.mp3"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link.mp3"),
                                                       withDestinationURL: folder.appendingPathComponent("a.mp3"))
        }

        func url(_ name: String) -> URL { paths.musicDirectory.appendingPathComponent("F00/\(name)") }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    /// The synthetic library (tracks 10-16) with files given by name.
    private func library(_ files: [UInt32: String]) throws -> ITLibrary {
        try ITunesDBParser.parse(SyntheticLibrary.database()).mappingTracks { track in
            guard let name = files[track.uniqueID] else { return track }
            return track.setting(.location, to: ":iPod_Control:Music:F00:\(name)")
        }
    }

    private func queue(removing ids: Set<UInt32>, from library: ITLibrary, on disk: Disk,
                       archive: URL? = nil) throws -> (changes: ChangeSet, queued: [URL]) {
        var changes = ChangeSet()
        let queued = changes.queueFiles(of: library.tracks.filter { ids.contains($0.uniqueID) },
                                        keeping: try library.removingTracks(uniqueIDs: ids),
                                        paths: disk.paths, files: LocalFileSystem(), keepCopiesIn: archive)
        return (changes, queued)
    }

    @Test("a regular file of a removed track: into the queue")
    func regularFile() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let result = try queue(removing: [10], from: library([10: "a.mp3", 11: "b.mp3"]), on: disk)
        #expect(result.queued == [disk.url("a.mp3")])
        #expect(result.changes.filesToDelete == [disk.url("a.mp3")])
        #expect(result.changes.archiveBeforeDelete.isEmpty)
    }

    @Test("a file a remaining track points to: not into the queue")
    func sharedWithSurvivor() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let result = try queue(removing: [10], from: library([10: "a.mp3", 11: "a.mp3"]), on: disk)
        #expect(result.queued.isEmpty)
    }

    @Test("two removed tracks with one file: the file once")
    func sharedBetweenRemoved() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let result = try queue(removing: [10, 11], from: library([10: "a.mp3", 11: "a.mp3"]), on: disk)
        #expect(result.queued == [disk.url("a.mp3")])
    }

    @Test("a folder and a link: not into the queue")
    func folderAndLink() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let result = try queue(removing: [10, 11], from: library([10: "F01.mp3", 11: "link.mp3"]), on: disk)
        #expect(result.queued.isEmpty)
    }

    @Test("a file already in the queue: not a second time")
    func alreadyQueued() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let library = try library([10: "a.mp3", 11: "b.mp3"])
        var changes = ChangeSet()
        let removed = library.tracks.filter { $0.uniqueID == 10 }
        let kept = try library.removingTracks(uniqueIDs: [10])
        changes.queueFiles(of: removed, keeping: kept, paths: disk.paths, files: LocalFileSystem(), keepCopiesIn: nil)
        let again = changes.queueFiles(of: removed, keeping: kept, paths: disk.paths, files: LocalFileSystem(), keepCopiesIn: nil)
        #expect(again.isEmpty)
        #expect(changes.filesToDelete.count == 1)
    }

    @Test("a folder for copies: the copy plan under a name from the tags")
    func archivePlan() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let archive = disk.root.appendingPathComponent("Copies")
        let result = try queue(removing: [10], from: library([10: "a.mp3"]), on: disk, archive: archive)
        let plan = try #require(result.changes.archiveBeforeDelete[disk.url("a.mp3")])
        #expect(plan.directory == archive)
        #expect(plan.fileName.hasSuffix(".mp3"))
    }

    @Test("files without an entry (ipodctl check): only regular files no track points to")
    func unreferencedFiles() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        var changes = ChangeSet()
        let queued = changes.queueUnreferencedFiles(
            [disk.url("a.mp3"), disk.url("b.mp3"), disk.url("F01.mp3"), disk.url("link.mp3")],
            in: try library([10: "a.mp3"]), paths: disk.paths, files: LocalFileSystem())
        #expect(queued == [disk.url("b.mp3")])
    }

    // MARK: - Log and tasks

    private func tracks(of album: String) throws -> [ITTrack] {
        try ITunesDBParser.parse(SyntheticLibrary.database()).tracks.filter { $0.album == album }
    }

    @Test("an empty queue; a task alone without an entry (ipodctl) is also something to write")
    func emptiness() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        #expect(ChangeSet().isEmpty)
        let result = try queue(removing: [10], from: library([10: "a.mp3"]), on: disk)
        #expect(result.changes.log.isEmpty)
        #expect(!result.changes.isEmpty)
    }

    @Test("artwork requested twice for the same album: one task, one entry")
    func coverRequeued() throws {
        let tracks = try tracks(of: "The Bends")
        let key = AlbumID(albumOf: tracks)
        let image = try WriteTests.image(red: 1, green: 0, blue: 0)
        var changes = ChangeSet()
        changes.queueFirstCover(image, sourceByteCount: 100, owner: tracks[0], tracks: tracks, album: "The Bends", for: key)
        changes.queueFirstCover(image, sourceByteCount: 200, owner: tracks[0], tracks: tracks, album: "The Bends", for: key)
        #expect(changes.log.count == 1)
        #expect(changes.artworkAdditions[key]?.sourceByteCount == 200)

        changes.queueCoverReplacement(image, slots: [], trackIDs: tracks.map(\.persistentID), album: "The Bends", for: key)
        #expect(changes.log.count == 1)
        #expect(changes.artworkAdditions.isEmpty && changes.artworkReplacements.count == 1)
        guard case .artworkReplaced? = changes.log.first?.kind else { Issue.record("\(changes.log)"); return }
    }

    @Test("a conversion requested twice: one entry, with the last folder for the original")
    func conversionRequeued() {
        var changes = ChangeSet()
        let source = URL(fileURLWithPath: "/tmp/x.wav")
        changes.queueConversion(trackID: 14, album: "The Bends", title: "Just", source: source, to: .appleLossless(sampleRate: 48_000),
                                fromLabel: "WAV 24", keepOriginalIn: nil)
        changes.queueConversion(trackID: 14, album: "The Bends", title: "Just", source: source, to: .appleLossless(sampleRate: 48_000),
                                fromLabel: "WAV 24", keepOriginalIn: URL(fileURLWithPath: "/tmp/Copies"))
        #expect(changes.log.count == 1)
        guard case .trackConverted(_, _, _, _, let saved)? = changes.log.first?.kind else { Issue.record("\(changes.log)"); return }
        #expect(saved == "/tmp/Copies")
    }

    @Test("a merge after a merge: the redirect goes to the copy that stays")
    func redirectChain() {
        var changes = ChangeSet()
        changes.redirect(playCounts: [1: 2], artworkOwners: [10: 20])
        changes.redirect(playCounts: [2: 3], artworkOwners: [20: 30])
        #expect(changes.playCountRedirects == [1: 3, 2: 3])
        #expect(changes.artworkOwnerRedirects == [10: 30, 20: 30])
    }

    @Test("after the write: the tasks that did not go in stay, with their entries; the rest of the log and the redirects disappear")
    func remainingAfterWrite() throws {
        let disk = try Disk(); defer { disk.cleanUp() }
        let bends = try tracks(of: "The Bends"), currents = try tracks(of: "Currents")
        let image = try WriteTests.image(red: 1, green: 0, blue: 0)
        let source = URL(fileURLWithPath: "/tmp/x.wav")
        var changes = try queue(removing: [10], from: library([10: "a.mp3"]), on: disk).changes
        changes.record(.albumMoved(album: "Currents", from: 0, to: 1))
        changes.redirect(playCounts: [1: 2], artworkOwners: [10: 20])
        changes.queueFirstCover(image, sourceByteCount: 1, owner: bends[0], tracks: bends, album: "The Bends",
                                for: AlbumID(albumOf: bends))
        changes.queueFirstCover(image, sourceByteCount: 1, owner: currents[0], tracks: currents, album: "Currents",
                                for: AlbumID(albumOf: currents))
        changes.queueConversion(trackID: 14, album: "The Bends", title: "Just", source: source, to: .appleLossless(sampleRate: 48_000),
                                fromLabel: "WAV 24", keepOriginalIn: nil)

        var completed = ChangeSet.Completed()
        completed.covers = [AlbumID(albumOf: bends)]
        completed.deletionsToRetry = [disk.url("a.mp3")]
        let next = changes.remaining(after: completed)

        #expect(next.artworkAdditions.keys.map { $0 } == [AlbumID(albumOf: currents)])
        #expect(next.conversions.keys.map { $0 } == [14])
        #expect(next.filesToDelete == [disk.url("a.mp3")])
        #expect(next.playCountRedirects.isEmpty && next.artworkOwnerRedirects.isEmpty)
        let kinds = next.log.map(\.kind)
        #expect(kinds.count == 3, "\(kinds)")
        #expect(kinds.contains { if case .artworkAdded("Currents", _) = $0 { true } else { false } })
        #expect(kinds.contains { if case .trackConverted = $0 { true } else { false } })
        #expect(kinds.contains { if case .filesLeftToDelete(1) = $0 { true } else { false } })
        let original = Set(changes.log.map(\.id))
        let taskEntries = next.log.filter { if case .filesLeftToDelete = $0.kind { false } else { true } }
        #expect(taskEntries.allSatisfy { original.contains($0.id) }, "the task entries are the same, with the request time")
    }

    @Test("after a write in which everything went in: the queue is empty")
    func remainingAfterFullWrite() throws {
        let bends = try tracks(of: "The Bends")
        var changes = ChangeSet()
        changes.record(.albumMoved(album: "Currents", from: 0, to: 1))
        changes.queueFirstCover(try WriteTests.image(red: 1, green: 0, blue: 0), sourceByteCount: 1, owner: bends[0],
                                tracks: bends, album: "The Bends", for: AlbumID(albumOf: bends))
        var completed = ChangeSet.Completed()
        completed.covers = [AlbumID(albumOf: bends)]
        #expect(changes.remaining(after: completed).isEmpty)
    }
}
