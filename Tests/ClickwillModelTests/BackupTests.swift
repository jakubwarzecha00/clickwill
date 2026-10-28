import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Backups on a fake iPod: an on-demand backup, a restore preview,
/// a restore keeping the play history, refusals.
@Suite("Backups")
@MainActor
struct BackupTests {

    /// Writing a rename of Currents -> "Currents (Deluxe)". Returns the backup from before the database write.
    private func writeRename(_ rig: WriteTests.Rig) async throws -> Snapshot {
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        _ = try await rig.model.apply()
        return try #require(rig.model.backups().first, "a backup before the database write")
    }

    @Test("an on-demand backup goes onto this iPod's backup list")
    func backUpNow() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        #expect(rig.model.backups().isEmpty)
        let made = try rig.model.backUpNow()
        #expect(rig.model.backups().map(\.id) == [made.id])
        #expect(made.deviceGUID == WriteTests.guid)
    }

    @Test("preview: what the write after the backup changed and what the restore will undo")
    func previewAfterWrite() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let before = try await writeRename(rig)

        let preview = try await rig.model.preview(before)
        #expect(preview.songCount == 7)
        #expect(preview.albumCount == 3)
        #expect(preview.songsAddedSince == 0 && preview.songsRemovedSince == 0 && preview.songsWithoutFile == 0)
        #expect(preview.writeAfter.edits.contains { $0.after == "Currents (Deluxe)" })
        #expect(preview.writeAfterUntil == nil, "the last write - comparison with the current state")
        #expect(preview.restoring.edits.contains { $0.before == "Currents (Deluxe)" && $0.after == "Currents" })
    }

    @Test("restore: the database from the backup, the play history from the current state, a backup of the state before the restore")
    func restoreKeepsPlays() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let before = try await writeRename(rig)
        // The iPod counted plays after the write.
        let played = try rig.onDisk().mappingTracks { track in
            guard track.uniqueID == 10 else { return track }
            var copy = track
            copy.playCount = 5
            return copy
        }
        try Hash58.sign(ITunesDBWriter.serialize(played), fireWireID: Hash58.fireWireID(fromHex: WriteTests.guid))
            .write(to: rig.paths.iTunesDB)
        await rig.model.load(try #require(rig.model.source))

        let undo = try await rig.model.restoreBackup(before)

        let disk = try rig.onDisk()
        #expect(disk.tracks.contains { $0.album == "Currents" })
        #expect(!disk.tracks.contains { $0.album == "Currents (Deluxe)" })
        #expect(disk.tracks.first { $0.uniqueID == 10 }?.playCount == 5, "plays do not go back")
        #expect(try rig.signedWithDeviceKey())
        #expect(rig.model.albums.contains { $0.title == "Currents" }, "the model reloaded")
        #expect(try rig.backups.readLibrary(of: undo).tracks.contains { $0.album == "Currents (Deluxe)" },
                "the backup from before the restore lets it be undone")
    }

    @Test("refusals: unsaved changes, demo mode")
    func refusals() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let made = try rig.model.backUpNow()
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .genre, to: "Psych")
        await #expect(throws: BackupRestoreError.self) { try await rig.model.restoreBackup(made) }

        let demo = LibraryModel(environment: rig.environment, demo: DemoMode(blocksWrites: true))
        await demo.load(try #require(rig.model.source))
        #expect(throws: WriteBlocked.demoCopy) { try demo.backUpNow() }
        await #expect(throws: WriteBlocked.demoCopy) { try await demo.restoreBackup(made) }
    }

    @Test("the service without a model: the preview skips backups with the same database")
    func previewSkipsTwins() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let service = BackupService(device: try #require(rig.model.device), store: try rig.backups)
        let first = try service.backUpNow()
        _ = try service.backUpNow()
        _ = try await writeRename(rig)    // a backup before the write - the same database as the two manual ones

        let all = service.list()
        #expect(all.count == 3)
        let preview = try service.preview(first, fallback: try #require(rig.model.library))
        #expect(preview.writeAfterUntil == nil, "twins skipped - comparison with the current state")
        #expect(preview.writeAfter.edits.contains { $0.after == "Currents (Deluxe)" })
    }
}
