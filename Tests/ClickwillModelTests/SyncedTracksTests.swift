import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Songs the iPod's own library sync rebuilds from their files (`OnDeviceSync`): removal and
/// a new cover refused before anything is queued, other edits and other albums as usual.
@Suite("Songs owned by the on-device sync")
@MainActor
struct SyncedTracksTests {

    /// The write rig with Aftermath turned into FLAC entries in `/Music/Aftermath/` and,
    /// with `sync`, the sync's state file - then loaded again.
    private func rig(sync: Bool = true) async throws -> WriteTests.Rig {
        let rig = try await WriteTests.rig(WriteTests.Fixture(cover: true))
        let library = try rig.onDisk().mappingTracks { track in
            guard track.album == "Aftermath" else { return track }
            var flac = track.setting(.location, to: ":Music:Aftermath:\(track.uniqueID).flac")
            flac.rawHeader.set(MhitLayout.fileTypeCode, OnDeviceSync.flacType)
            return flac
        }
        let folder = rig.paths.mountPoint.appendingPathComponent("Music/Aftermath")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for track in library.tracks where track.album == "Aftermath" {
            try Data(count: Int(track.sizeBytes)).write(to: folder.appendingPathComponent("\(track.uniqueID).flac"))
        }
        if sync {
            let state = rig.paths.mountPoint.appendingPathComponent("FLAC")
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
            try Data(Array("FLSY".utf8) + [4, 0, 0, 0]).write(to: state.appendingPathComponent("libsync.state"))
        }
        try Hash58.sign(ITunesDBWriter.serialize(library), fireWireID: Hash58.fireWireID(fromHex: WriteTests.guid))
            .write(to: rig.paths.iTunesDB)
        let device = try IPodDevice.open(try #require(IPodVolume.at(rig.paths.mountPoint)))
        await rig.model.load(.device(device))
        return rig
    }

    @Test("removing an owned song or album is refused; nothing is queued")
    func removalRefused() async throws {
        let rig = try await rig(); defer { rig.cleanUp() }
        let album = try rig.album("Aftermath")
        #expect(rig.model.isSyncedOnDevice(album))
        let row = try rig.row("Paint It Black", in: "Aftermath")
        #expect(rig.model.isSyncedOnDevice(row))

        #expect(throws: SyncedTracksRefusal.removal(songs: 1)) { try rig.model.deleteTrack(row, in: album) }
        #expect(throws: SyncedTracksRefusal.removal(songs: 2)) { try rig.model.deleteAlbum(album) }
        #expect(!rig.model.hasPendingChanges)
        #expect(rig.model.tracks(of: album).count == 2)
    }

    @Test("a new cover for an owned album is refused")
    func artworkRefused() async throws {
        let rig = try await rig(); defer { rig.cleanUp() }
        let image = try WriteTests.image(red: 0, green: 1, blue: 0)
        #expect(throws: SyncedTracksRefusal.artwork(album: "Aftermath")) {
            try rig.model.setArtwork(for: try rig.album("Aftermath"), image: image)
        }
        #expect(!rig.model.hasPendingChanges)
    }

    @Test("other albums and other edits as usual; owned files count as present")
    func restUnchanged() async throws {
        let rig = try await rig(); defer { rig.cleanUp() }
        let other = try rig.album("Currents")
        #expect(!rig.model.isSyncedOnDevice(other))
        try rig.model.deleteTrack(try rig.row("Eventually", in: "Currents"), in: other)
        rig.model.renameTrack(try rig.row("Paint It Black", in: "Aftermath"), in: try rig.album("Aftermath"), to: "Paint It, Black")
        #expect(rig.model.changes.log.count == 2)
        #expect(try rig.album("Aftermath").missingFiles == 0, "the FLAC files lie in /Music")
    }

    @Test("without the sync a FLAC entry is an ordinary one: no file, removable")
    func withoutSync() async throws {
        let rig = try await rig(sync: false); defer { rig.cleanUp() }
        let album = try rig.album("Aftermath")
        #expect(rig.model.onDeviceSync == nil)
        #expect(!rig.model.isSyncedOnDevice(album))
        #expect(album.missingFiles == 2)
        try rig.model.deleteTrack(try rig.row("Paint It Black", in: "Aftermath"), in: album)
        #expect(rig.model.hasPendingChanges)
    }
}
