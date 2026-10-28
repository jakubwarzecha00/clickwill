import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

@Suite("Queue of tracks to add")
@MainActor
struct AdditionsTests {

    static func candidate(
        title: String, album: String = "Loveless", file: String = "a.mp3",
        verdict: AudioCompatibility.Verdict = .supported, bytes: UInt32 = 4_000_000
    ) -> AudioImport.Candidate {
        let draft = TrackDraft(title: title, artist: "My Bloody Valentine",
                               albumArtist: "My Bloody Valentine", album: album,
                               sizeBytes: bytes, kind: .mp3, relativePath: "")
        return AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/\(file)"), draft: draft,
                                     verdict: verdict, formatLabel: "MP3 44.1 kHz 256 kbps", artwork: nil)
    }

    /// A model with the synthetic library loaded (Aftermath, The Bends,
    /// Currents) - edit commands work only on a loaded library.
    static func model() async throws -> LibraryModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("additions-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let model = LibraryModel()
        await model.load(.snapshot(root))
        return model
    }

    @Test("added files give one log item, not one per track")
    func oneSummaryRow() async throws {
        let model = try await Self.model()
        model.queueAdditions([Self.candidate(title: "Only Shallow", file: "1.mp3"),
                     Self.candidate(title: "Loomer", file: "2.mp3"),
                     Self.candidate(title: "Touched", file: "3.mp3")])

        #expect(model.changes.additions.count == 3)
        #expect(model.changes.log.count == 1)
        guard case .tracksAdded(let tracks, let albums, _, _)? = model.changes.log.first?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.first?.kind))"); return
        }
        #expect(tracks == 3 && albums == 1)
    }

    @Test("the same file does not go in twice")
    func noDuplicates() async throws {
        let model = try await Self.model()
        model.queueAdditions([Self.candidate(title: "Only Shallow", file: "1.mp3")])
        let refused = model.queueAdditions([Self.candidate(title: "Only Shallow", file: "1.mp3")])

        #expect(model.changes.additions.count == 1)
        #expect(refused.count == 1)
        guard case .alreadyQueued = refused[0].reason else { Issue.record("\(refused)"); return }
        #expect(refused[0].subject == "Only Shallow")
    }

    @Test("a file we cannot transcode is rejected with a reason")
    func hopelessRefused() async throws {
        let model = try await Self.model()
        let refused = model.queueAdditions([Self.candidate(
            title: "Quadraphonic", file: "q.wav",
            verdict: .rejected(reason: "4 channels; the iPod plays mono and stereo only"))])

        #expect(model.changes.additions.isEmpty)
        #expect(model.changes.log.isEmpty)
        guard case .cannotPlay(let reason)? = refused.first?.reason else { Issue.record("\(refused)"); return }
        #expect(reason?.contains("4 channels") == true)
    }

    @Test("a file to transcode goes into the queue and is counted separately")
    func convertibleCounted() async throws {
        let model = try await Self.model()
        model.queueAdditions([
            Self.candidate(title: "Only Shallow", file: "1.mp3"),
            Self.candidate(title: "Sometimes", file: "2.flac",
                           verdict: .convertible(reason: "FLAC is not a format the iPod can read",
                                                 target: .appleLossless(sampleRate: 44_100))),
        ])
        #expect(model.changes.additions.count == 2)
        #expect(model.changes.additions.filter(\.needsConversion).count == 1)
        guard case .tracksAdded(_, _, _, let converting)? = model.changes.log.first?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.first?.kind))"); return
        }
        #expect(converting == 1)
    }

    @Test("two albums at once are counted as two")
    func twoAlbums() async throws {
        let model = try await Self.model()
        model.queueAdditions([Self.candidate(title: "Only Shallow", album: "Loveless", file: "1.mp3"),
                     Self.candidate(title: "Soon", album: "Glider", file: "2.mp3")])
        guard case .tracksAdded(_, let albums, _, _)? = model.changes.log.first?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.first?.kind))"); return
        }
        #expect(albums == 2)
    }

    @Test("an iPod swapped at the path: the queue stops before the first file")
    func abortsWhenVolumeChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("abort-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IPodPaths(mountPoint: root.appendingPathComponent("iPod"))
        try FileManager.default.createDirectory(at: paths.musicDirectory.appendingPathComponent("F00"), withIntermediateDirectories: true)
        let source = root.appendingPathComponent("a.mp3")
        try Data(repeating: 1, count: 1000).write(to: source)
        let library = try ITunesDBParser.parse(SyntheticLibrary.database())
        let addition = PendingAddition(Self.candidate(title: "Only Shallow", file: "a.mp3"))
        let moved = PendingAddition(id: addition.id, draft: addition.draft, source: source, verdict: .supported,
                                    formatLabel: addition.formatLabel, cover: nil)

        let outcome = await TrackAdditionRunner.run([moved], into: library, paths: paths,
                                                    ensureMounted: { throw ITDBError.writeRefused(.deviceSwapped) })
        #expect(outcome.aborted)
        #expect(outcome.copied.isEmpty && outcome.done.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.musicDirectory.appendingPathComponent("F00").path).isEmpty)
    }

    @Test("Discard All and loading another library clear the add queue")
    func reloadClearsQueue() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let model = LibraryModel(); await model.load(.snapshot(root))
        let before = model.coverFlowDisplay.count
        model.queueAdditions([Self.candidate(title: "Only Shallow", album: "Loveless", file: "1.mp3")])
        #expect(model.coverFlowDisplay.count == before + 1)

        await model.discardChanges()
        #expect(model.changes.additions.isEmpty, "until 0.2.2 the queue survived Discard All")
        #expect(model.changes.log.isEmpty)
        #expect(model.coverFlowDisplay.count == before)
    }

    @Test("a new album from the queue stands in Cover Flow right away and disappears when withdrawn")
    func pendingAlbumInCoverFlow() async throws {
        let model = try await Self.model()
        model.queueAdditions([Self.candidate(title: "Only Shallow", album: "Loveless", file: "1.mp3"),
                     Self.candidate(title: "Loomer", album: "Loveless", file: "2.mp3"),
                     Self.candidate(title: "Soon", album: "Glider", file: "3.mp3")])

        #expect(model.pendingAlbums.map(\.card.title).sorted() == ["Glider", "Loveless"])
        #expect(model.coverFlowDisplay.count == model.coverFlowAlbums.count + 2)
        #expect(model.coverFlowDisplay.filter(\.isPending).count == 2)
        let loveless = try #require(model.pendingAlbums.first { $0.card.title == "Loveless" })
        #expect(loveless.card.trackCount == 2)
        #expect(loveless.card.trackIndices.isEmpty)

        model.removeQueuedAlbum(loveless)
        #expect(model.pendingAlbums.map(\.card.title) == ["Glider"])
        #expect(model.changes.additions.count == 1)
        guard case .tracksAdded(let tracks, _, _, _)? = model.changes.log.first?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.first?.kind))"); return
        }
        #expect(tracks == 1)

        model.removeQueuedAddition(model.changes.additions[0].id)
        #expect(model.pendingAlbums.isEmpty)
        #expect(model.coverFlowDisplay.count == model.coverFlowAlbums.count)
    }

    @Test("a track added to a specific album does not create a new card")
    func placedSongIsNotPendingAlbum() async throws {
        let model = try await Self.model()
        var addition = PendingAddition(Self.candidate(title: "Only Shallow", file: "1.mp3"))
        addition.placement = AlbumPlacement(album: "Loveless",
                                            albumKey: AlbumKey(album: "Loveless", albumArtist: "My Bloody Valentine"),
                                            index: 0)
        #expect(model.changes.queueAddition(addition) == nil)
        #expect(model.pendingAlbums.isEmpty)
    }

}
