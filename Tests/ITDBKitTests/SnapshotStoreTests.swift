import Testing
import Foundation
@testable import ITDBKit

/// The backup store. Until now without tests of its own, although it is the safety
/// net of the whole project - and now it is restored from in the app.
@Suite("Backups")
struct SnapshotStoreTests {

    /// A fake iPod in a temporary folder, with a real database and artwork.
    private struct Rig {
        let root: URL
        let device: IPodDevice
        let store: SnapshotStore
        var control: URL { device.paths.control }

        func write(_ text: String, to path: String) throws {
            let url = control.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func read(_ path: String) throws -> String {
            String(decoding: try Data(contentsOf: control.appendingPathComponent(path)), as: UTF8.self)
        }
        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    private func rig() throws -> Rig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-store-\(UUID().uuidString)", isDirectory: true)
        let mount = root.appendingPathComponent("iPod", isDirectory: true)
        let paths = IPodPaths(mountPoint: mount)
        try FileManager.default.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        try ITunesDBWriter.serialize(try LibraryFixture.standard()).write(to: paths.iTunesDB)

        let format = DatabaseFormat(headerLength: 244, version: 117, databaseID: 0xABCD, signing: .hash58)
        let device = IPodDevice(
            volume: IPodVolume(paths: paths, name: "Test iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
            fireWireID: nil, format: format,
            model: IPodModel(modelNumber: nil, name: "Test", source: .databaseOnly))
        let store = SnapshotStore(root: root.appendingPathComponent("Backups", isDirectory: true))
        return Rig(root: root, device: device, store: store)
    }

    @Test("a restore gives back the files from the moment of the backup")
    func roundTrip() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        try rig.write("artwork v1", to: "Artwork/ArtworkDB")
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual, note: "test")

        try rig.write("artwork v2", to: "Artwork/ArtworkDB")
        try rig.store.restore(snapshot, to: rig.device)
        #expect(try rig.read("Artwork/ArtworkDB") == "artwork v1")
    }

    @Test("artwork created after the backup disappears on restore, the iPod's files in iTunes stay")
    func restoreRemovesArtworkCreatedLater() throws {
        // A nano 2G after Finder: the artwork folder empty, the backup without ArtworkDB.
        let rig = try rig(); defer { rig.cleanUp() }
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual)

        try rig.write("new", to: "Artwork/ArtworkDB")
        try rig.write("pixels", to: "Artwork/F1027_1.ithmb")
        try rig.write("plays", to: "iTunes/Play Counts")
        try rig.store.restore(snapshot, to: rig.device, include: SnapshotStore.artworkOnly)

        let exists = { (path: String) in FileManager.default.fileExists(atPath: rig.control.appendingPathComponent(path).path) }
        #expect(!exists("Artwork/ArtworkDB"))
        #expect(!exists("Artwork/F1027_1.ithmb"))
        #expect(exists("iTunes/Play Counts"), "a file created by the iPod carries the listening history")
    }

    @Test("a partial restore does not touch the rest")
    func partialRestore() throws {
        // This is how the app restores: the database goes through the regular write path,
        // and only the artwork is taken directly from the backup.
        let rig = try rig(); defer { rig.cleanUp() }
        try rig.write("artwork v1", to: "Artwork/ArtworkDB")
        try rig.write("prefs v1", to: "iTunes/iTunesPrefs")
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual)

        try rig.write("artwork v2", to: "Artwork/ArtworkDB")
        try rig.write("prefs v2", to: "iTunes/iTunesPrefs")
        try rig.store.restore(snapshot, to: rig.device, include: SnapshotStore.artworkOnly)

        #expect(try rig.read("Artwork/ArtworkDB") == "artwork v1")
        #expect(try rig.read("iTunes/iTunesPrefs") == "prefs v2", "nothing outside the filter is overwritten")
    }

    @Test("a damaged backup does not touch the device")
    func corruptedBackupTouchesNothing() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        try rig.write("artwork v1", to: "Artwork/ArtworkDB")
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual)
        try rig.write("artwork v2", to: "Artwork/ArtworkDB")

        // Someone (or the disk) changed a file in the backup after it was made.
        try Data("damaged".utf8).write(to: rig.store.fileURL(in: snapshot, path: "Artwork/ArtworkDB"))

        #expect(throws: ITDBError.self) { try rig.store.restore(snapshot, to: rig.device) }
        #expect(try rig.read("Artwork/ArtworkDB") == "artwork v2",
                "checksums are checked before the first write, not during it")
    }

    @Test("the library from a backup can be read without restoring")
    func readsLibraryFromBackup() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual)
        let library = try rig.store.readLibrary(of: snapshot)
        #expect(library.tracks.count == (try LibraryFixture.standard()).tracks.count)
    }

    @Test("a backup goes under the device identity even without a GUID")
    func identityWithoutGUID() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual)
        #expect(snapshot.deviceGUID == "DB-000000000000ABCD")
        #expect(try rig.store.list(deviceGUID: rig.device.identity).map(\.id) == [snapshot.id])
    }

    @Test("the artwork filter looks at path components, not at the string prefix")
    func artworkFilterByComponents() {
        #expect(SnapshotStore.artworkOnly("Artwork/ArtworkDB"))
        #expect(!SnapshotStore.artworkOnly("Artwork/../iTunes/iTunesDB"))
        #expect(!SnapshotStore.artworkOnly("Artworks/F1027_1.ithmb"))
        #expect(!SnapshotStore.artworkOnly("iTunes/iTunesDB"))
    }

    @Test("a manifest pointing to another folder does not reach the list and cannot be deleted")
    func manifestMustMatchItsDirectory() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual)
        // A folder outside the backups that a crafted manifest tries to point to.
        let victim = rig.root.appendingPathComponent("victim", isDirectory: true)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)

        let deviceDirectory = rig.store.root.appendingPathComponent(rig.device.identity, isDirectory: true)
        let forged = deviceDirectory.appendingPathComponent("20990101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: forged, withIntermediateDirectories: true)
        let manifest = try Data(contentsOf: deviceDirectory.appendingPathComponent(snapshot.id).appendingPathComponent("manifest.json"))
        let text = String(decoding: manifest, as: UTF8.self).replacingOccurrences(of: snapshot.id, with: "../../victim")
        try Data(text.utf8).write(to: forged.appendingPathComponent("manifest.json"))

        #expect(try rig.store.list(deviceGUID: rig.device.identity).map(\.id) == [snapshot.id])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let bad = try decoder.decode(Snapshot.self, from: Data(text.utf8))
        #expect(throws: ITDBError.self) { try rig.store.delete(bad) }
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

    @Test("two backups in the same second: separate folders, the first untouched")
    func twoCapturesInOneSecond() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        try rig.write("artwork v1", to: "Artwork/ArtworkDB")
        let first = try rig.store.capture(from: rig.device, reason: .manual, note: "before files")
        try rig.write("artwork v2", to: "Artwork/ArtworkDB")
        let second = try rig.store.capture(from: rig.device, reason: .manual, note: "before the database")

        #expect(first.id != second.id)
        try rig.store.verify(first)
        try rig.store.restore(first, to: rig.device)
        #expect(try rig.read("Artwork/ArtworkDB") == "artwork v1")
        #expect(try rig.store.list(deviceGUID: rig.device.identity).map { $0.id } == [second.id, first.id], "the newest first")
    }

    // MARK: - Backup reason

    @Test("the backup reason stored in the manifest and read from the list")
    func reasonInManifest() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        _ = try rig.store.capture(from: rig.device, reason: .beforeWrite(changes: 3), note: "anything")
        let listed = try #require(try rig.store.list(deviceGUID: rig.device.identity).first)
        #expect(listed.reason == .beforeWrite(changes: 3))
        #expect(listed.effectiveReason == .beforeWrite(changes: 3), "the note does not matter when there is a reason")
    }

    @Test("a backup from before reasons: a manifest without the field reads, the reason from the note")
    func legacyManifest() throws {
        let rig = try rig(); defer { rig.cleanUp() }
        // A note as versions up to 0.2.5 wrote it (in Polish) - the parser still reads these.
        let snapshot = try rig.store.capture(from: rig.device, reason: .manual, note: "Clickwill: 3 zmian")
        // A manifest as versions up to 0.2.5 wrote it - without `reason`.
        let url = rig.store.manifestURL(forDevice: snapshot.deviceGUID, snapshot: snapshot.id)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["reason"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let listed = try #require(try rig.store.list(deviceGUID: rig.device.identity).first)
        #expect(listed.reason == nil)
        #expect(listed.effectiveReason == .beforeWrite(changes: 3))
    }

    @Test("notes of old versions (written in Polish): each one the code wrote has its reason")
    func legacyNotes() {
        let cases: [(String?, SnapshotReason?)] = [
            ("Clickwill: kopia reczna", .manual),
            ("Clickwill: przed przywroceniem kopii 2026-10-01T10-00-00Z", .beforeRestore),
            ("Clickwill: przed naprawa okladek", .beforeArtworkRepair),
            ("Clickwill: przed zmianami plikow", .beforeFiles),
            ("Clickwill: przed konwersja", .beforeFiles),
            ("Clickwill: przed przywroceniem plikow", .beforeFiles),
            ("Clickwill: 1 zmian", .beforeWrite(changes: 1)),
            ("przed zapisem bazy", .beforeWrite(changes: nil)),
            ("ipodctl artwork --add Cold Front", nil),
            (nil, nil),
        ]
        for (note, reason) in cases {
            #expect(SnapshotReason(legacyNote: note) == reason, "\(note ?? "nil")")
        }
    }

}

/// Play history when restoring a backup. A backup rolls back the library,
/// but has no right to roll back listening.
@Suite("Play history when restoring")
struct PlayHistoryTests {

    private func library(playCount: UInt32, lastPlayed: Date?) throws -> ITLibrary {
        try LibraryFixture.standard().mappingTracks { track in
            var copy = track
            copy.playCount = playCount
            copy.lastPlayed = lastPlayed
            return copy
        }
    }

    @Test("plays from now carry over to the restored backup")
    func carriesForward() throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_790_000_000)
        let backup = try library(playCount: 3, lastPlayed: old)
        let now = try library(playCount: 11, lastPlayed: recent)

        let restored = backup.carryingPlayHistory(from: now)
        #expect(restored.tracks.allSatisfy { $0.playCount == 11 && $0.lastPlayed == recent })
    }

    @Test("never decreases")
    func neverDecreases() throws {
        // A track may have been played more in the backup's state than now (e.g. after
        // the counters were reset). We take the larger value, not the newer one.
        let backup = try library(playCount: 20, lastPlayed: Date(timeIntervalSince1970: 1_790_000_000))
        let now = try library(playCount: 4, lastPlayed: Date(timeIntervalSince1970: 1_700_000_000))

        let restored = backup.carryingPlayHistory(from: now)
        #expect(restored.tracks.allSatisfy { $0.playCount == 20 })
        #expect(restored.tracks.allSatisfy { $0.lastPlayed == Date(timeIntervalSince1970: 1_790_000_000) })
    }

    @Test("a track that does not exist today stays with what it had in the backup")
    func keepsBackupForUnknownSongs() throws {
        let backup = try library(playCount: 7, lastPlayed: nil)
        let empty = backup.mappingTracks { track in
            var copy = track
            copy.persistentID = track.persistentID &+ 0x1_0000_0000   // other tracks
            return copy
        }
        let restored = backup.carryingPlayHistory(from: empty)
        #expect(restored.tracks.allSatisfy { $0.playCount == 7 })
    }


}
