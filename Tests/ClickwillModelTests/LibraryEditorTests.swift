import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Edit commands on `LibraryEditor` - without the model, on a fake iPod.
@Suite("Edit commands")
@MainActor
struct LibraryEditorTests {

    private func editor(_ rig: WriteTests.Rig) throws -> LibraryEditor {
        let session = try LibrarySession.open(try #require(rig.model.source))
        let catalog = AlbumCatalog(library: session.library, artwork: session.artwork, missingFiles: session.missingFileIDs)
        return LibraryEditor(session: session, changes: ChangeSet(), catalog: catalog, formatVerdicts: [:], formatLabels: [:])
    }

    @Test("deleting an album without the model: the records disappear, the files with a copy plan in the queue, one log entry")
    func deleteAlbumWithoutModel() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        var editor = try editor(rig)
        let bends = try #require(editor.catalog.albums.first { $0.title == "The Bends" })
        let archive = rig.root.appendingPathComponent("Copies", isDirectory: true)

        let removed = try editor.deleteAlbum(bends, keepCopiesIn: archive)

        #expect(removed == 3)
        #expect(!editor.library.tracks.contains { $0.album == "The Bends" })
        #expect(editor.changes.filesToDelete.count == 3)
        #expect(editor.changes.archiveBeforeDelete.count == 3)
        #expect(editor.changes.archiveBeforeDelete.values.allSatisfy { $0.directory == archive })
        #expect(editor.changes.log.count == 1)
        #expect(editor.libraryChanged)
        #expect(rig.model.albums.contains { $0.title == "The Bends" }, "the model does not know about the edit on the copy")
    }

    @Test("a command with only the queue does not change the library")
    func queueOnlyCommand() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        var editor = try editor(rig)
        let draft = TrackDraft(title: "New", artist: "A", albumArtist: "A", album: "New album",
                               sizeBytes: 1000, kind: .mp3, relativePath: "")
        let refused = editor.queueAdditions([AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/new.mp3"), draft: draft,
                                                                   verdict: .supported, formatLabel: "MP3", artwork: nil)])
        #expect(refused.isEmpty)
        #expect(editor.changes.additions.count == 1)
        #expect(!editor.libraryChanged)
    }

    @Test("an error halfway through a command: the model stays as it was")
    func failedCommandLeavesModelUntouched() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let tracksBefore = rig.model.library?.tracks.map(\.uniqueID)
        struct Failure: Error {}

        #expect(throws: Failure.self) {
            try rig.model.edit { editor in
                let bends = try #require(editor.catalog.albums.first { $0.title == "The Bends" })
                _ = try editor.deleteAlbum(bends, keepCopiesIn: nil)
                throw Failure()
            }
        }

        #expect(rig.model.library?.tracks.map(\.uniqueID) == tracksBefore)
        #expect(rig.model.changes.filesToDelete.isEmpty)
        #expect(rig.model.changes.log.isEmpty)
        #expect(rig.model.albums.contains { $0.title == "The Bends" })
    }

    @Test("editing through the model rebuilds the cards and returns the card after a rename")
    func editThroughModel() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let card = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        #expect(card.title == "Currents (Deluxe)")
        #expect(rig.model.albums.contains { $0.id == card.id })
        #expect(rig.model.changes.log.count == 1)
    }
}
