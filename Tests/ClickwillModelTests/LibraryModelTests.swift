import Foundation
import CoreGraphics
import Testing
import ITDBKit
@testable import ClickwillModel

/// A snapshot in the `files/iTunes/iTunesDB` layout built from the synthetic database.
private func makeSnapshot(_ data: Data) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("clickwill-test-\(UUID().uuidString)", isDirectory: true)
    let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
    try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
    try data.write(to: itunes.appendingPathComponent("iTunesDB"))
    return root
}

@Suite("Library model")
@MainActor
struct LibraryModelTests {

    @Test("the error state is equal by accident - the error carries the detail, not equality")
    func failureEqualityByCase() {
        struct A: Error {}; struct B: Error {}
        #expect(LibraryModel.Failure.loading(A()) == .loading(B()))
        #expect(LibraryModel.Failure.disconnected(unsavedChanges: 1) != .disconnected(unsavedChanges: 2))
        #expect(LibraryModel.Failure.loading(A()) != .disconnected(unsavedChanges: 0))
    }

    @Test("an edit command without a loaded library does nothing - artwork included")
    func editingWithoutLibraryDoesNothing() throws {
        let model = LibraryModel()
        let image = try WriteTests.image(red: 1, green: 0, blue: 0)
        let card = AlbumCard(id: .album(1), trackIndices: [], trackIDs: [], title: "X", artist: "Y", year: nil, genre: nil,
                             trackCount: 1, duration: 0, artworkTrackID: nil, missingFiles: 0, isCompilation: false,
                             artistSortKey: "Y")
        try model.setArtwork(for: card, image: image)
        #expect(model.changes.isEmpty)
    }

    @Test("a snapshot loads and gives cards in iPod order")
    func loadsSnapshot() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))

        #expect(model.state == .loaded)
        #expect(!model.isWritable)
        #expect(model.albums.map(\.title) == ["Aftermath", "The Bends", "Currents"])
        #expect(model.albums[1].trackCount == 3)
        #expect(model.albums[1].artist == "Radiohead")
        // A snapshot has no Music folder - file presence cannot be judged,
        // so nothing is marked as missing.
        #expect(!model.canCheckFiles)
        #expect(model.albums[1].missingFiles == 0)
        #expect(model.tracks(of: model.albums[1]).map(\.title) == ["Planet Telex", "Bones", "Just"])
    }

    @Test("moving tracks goes into the log and into the library")
    func editsAreStagedAndApplied() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))

        let bends = model.albums[1]
        try model.moveTracks(in: bends, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(model.tracks(of: bends).map(\.title) == ["Just", "Planet Telex", "Bones"])

        #expect(model.changes.log.count == 1)
        guard case .trackMoved(_, let track, let from, let to) = model.changes.log[0].kind else {
            Issue.record("change: \(model.changes.log[0].kind)"); return
        }
        #expect(track == "Just" && from == 2 && to == 0)
    }

    @Test("a removed track disappears from the card and is marked as destructive")
    func deleteTrack() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))

        let bends = model.albums[1]
        let bones = try #require(model.tracks(of: bends).first { $0.title == "Bones" })
        try model.deleteTrack(bones, in: bends)

        #expect(model.trackCount == 6)
        #expect(model.albums[1].trackCount == 2)
        #expect(model.tracks(of: model.albums[1]).map(\.title) == ["Planet Telex", "Just"])
        #expect(model.changes.log.last?.isDestructive == true)
        #expect(model.library?.browseIndex(.album)?.isPermutation(of: 6) == true)
    }

    @Test("discarding changes goes back to the state from disk")
    func discard() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))
        try model.moveTracks(in: model.albums[1], fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(model.hasPendingChanges)

        await model.discardChanges()
        #expect(!model.hasPendingChanges)
        #expect(model.tracks(of: model.albums[1]).map(\.title) == ["Planet Telex", "Bones", "Just"])
    }

    @Test("writing in snapshot mode is rejected")
    func applyRefusedForSnapshot() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))
        await #expect(throws: WriteBlocked.notFromDevice) { _ = try await model.apply() }
    }

    @Test("only a regular file inside Music is deletable")
    func deletableFileCheck() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-del-\(UUID().uuidString)")
        let music = root.appendingPathComponent("iPod_Control/Music/F00", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let musicRoot = root.appendingPathComponent("iPod_Control/Music")
        let file = music.appendingPathComponent("ABCD.mp3")
        try Data([1, 2, 3]).write(to: file)
        let outside = root.appendingPathComponent("iPod_Control/iTunes.mp3")
        try Data([1]).write(to: outside)
        let link = music.appendingPathComponent("LINK.mp3")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        #expect(DeviceFiles.isDeletableAudioFile(file, under: musicRoot, files: LocalFileSystem()))
        #expect(!DeviceFiles.isDeletableAudioFile(music, under: musicRoot, files: LocalFileSystem()))          // a folder
        #expect(!DeviceFiles.isDeletableAudioFile(outside, under: musicRoot, files: LocalFileSystem()))        // outside Music
        #expect(!DeviceFiles.isDeletableAudioFile(link, under: musicRoot, files: LocalFileSystem()))           // a link
        #expect(!DeviceFiles.isDeletableAudioFile(musicRoot, under: musicRoot, files: LocalFileSystem()))      // the Music folder itself
    }

    @Test("the order intent rebuilds the jump bar with full coverage")
    func intentRebuildsJumpTable() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))
        let library = try #require(model.library)
        var intent = library.captureOrderIntent()
        intent.albums.reverse()
        let (applied, report) = try library.applyingOrderIntent(intent)
        #expect(report.changed)
        let jump = try #require(applied.jumpTable(.album))
        #expect(jump.entries.reduce(0) { $0 + Int($1.count) } == 7)
        // In this fixture "The Bends" has no sortAlbum field, so it counts under T.
        #expect(jump.entries.map(\.letter) == [67, 84, 65])
    }

    @Test("moving within an array keeps the SwiftUI semantics")
    func arrayMoveSemantics() {
        var a = [0, 1, 2, 3, 4]
        a.moving(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        #expect(a == [4, 0, 1, 2, 3])
        a = [0, 1, 2, 3, 4]
        a.moving(fromOffsets: IndexSet(integer: 0), toOffset: 5)
        #expect(a == [1, 2, 3, 4, 0])
        a = [0, 1, 2, 3, 4]
        a.moving(fromOffsets: IndexSet([1, 2]), toOffset: 4)
        #expect(a == [0, 3, 1, 2, 4])
    }
}

@Suite("Deleting an album and disconnecting the device")
@MainActor
struct AlbumDeletionTests {

    /// A snapshot has no Music folder, so no file is deletable -
    /// here we check the database part and the log, not the files themselves.
    static func loaded() async throws -> (LibraryModel, URL) {
        let root = try makeSnapshot(SyntheticLibrary.database())
        let model = LibraryModel()
        await model.load(.snapshot(root))
        return (model, root)
    }

    @Test("deleting an album takes all its tracks and gives one log entry")
    func deleteAlbumRemovesEverything() async throws {
        let (model, root) = try await Self.loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        let album = try #require(model.albums.first { $0.trackCount > 1 })
        let before = model.trackCount
        let count = try model.deleteAlbum(album)

        #expect(count == album.trackCount)
        #expect(model.trackCount == before - album.trackCount)
        #expect(!model.albums.contains { $0.id == album.id })
        let deletions = model.changes.log.filter { if case .albumDeleted = $0.kind { return true } else { return false } }
        #expect(deletions.count == 1)
        #expect(deletions.first?.isDestructive == true)
    }

    @Test("the summary says where the copies go, when we ask for them")
    func summaryNamesTheCopies() async throws {
        let (model, root) = try await Self.loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        let album = try #require(model.albums.first)
        try model.deleteAlbum(album, keepCopiesIn: URL(fileURLWithPath: "/tmp/copies"))
        guard case .albumDeleted(_, _, _, _, let copies)? = model.changes.log.last?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.last?.kind))"); return
        }
        #expect(copies == "/tmp/copies")
    }

    @Test("disconnecting the device does not affect a library loaded from a snapshot")
    func snapshotSurvivesUnmount() async throws {
        let (model, root) = try await Self.loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = model.trackCount
        #expect(model.deviceDisconnected() == false)
        #expect(model.trackCount == before)
    }
}

@Suite("New artwork preview")
@MainActor
struct ArtworkPreviewTests {

    static func image() -> CGImage {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }

    /// An album without artwork has no record in ArtworkDB, so the card has no
    /// natural hook for an image. Without a hook the preview had nowhere to
    /// show, and choosing artwork looked like it failed.
    @Test("an album card without artwork still has something to hold the preview")
    func coverlessAlbumHasAnchor() async throws {
        let root = try makeSnapshot(SyntheticLibrary.database())
        defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel()
        await model.load(.snapshot(root))

        let album = try #require(model.albums.first)
        #expect(album.artworkTrackID != nil)
        #expect(model.artwork(for: album.artworkTrackID) == nil)
    }
}
