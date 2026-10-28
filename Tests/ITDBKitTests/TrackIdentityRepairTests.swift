import Testing
import Foundation
@testable import ITDBKit

/// Two identity defects with the same symptom: the artwork in Cover Flow
/// is there, and for the song playing it is not. The causes are separate,
/// so the tests are separate too.
@Suite("Track and album identity")
struct TrackIdentityRepairTests {

    // MARK: - 0xA8

    /// As on the Classic: one album has zero at 0xA8, the rest carry the identifier.
    @Test("a missing second copy of the identifier is restored")
    func restoresSecondaryIdentifier() throws {
        // The fixture has zero everywhere (the nano layout) - first the Classic layout.
        let library = try LibraryFixture.standard().mappingTracks { $0.restoringSecondaryPersistentID() }
        let album = try #require(library.tracks.first?.album)
        let cleared = library.mappingTracks { track in
            guard track.album == album else { return track }
            var copy = track
            for i in 0..<8 { copy.rawHeader[0xA8 + i] = 0 }
            return copy
        }
        let broken = cleared.tracks.count { $0.secondaryPersistentID == 0 }
        #expect(broken > 0 && broken < cleared.tracks.count)

        let outcome = cleared.repairingSecondaryIdentifiers()
        #expect(outcome.repaired == [album: broken])
        for track in outcome.library.tracks {
            #expect(track.secondaryPersistentID == track.persistentID)
        }
    }

    /// As on a nano 2G after Finder: zero in every track is the device's norm.
    @Test("a library without the second copy at all - the repair touches nothing")
    func deviceWithoutSecondaryIdentifiers() throws {
        let cleared = try LibraryFixture.standard().mappingTracks { track in
            var copy = track
            for i in 0..<8 { copy.rawHeader[0xA8 + i] = 0 }
            return copy
        }
        #expect(!cleared.usesSecondaryPersistentID)
        let outcome = cleared.repairingSecondaryIdentifiers()
        #expect(outcome.repaired.isEmpty)
        #expect(outcome.library.tracks.allSatisfy { $0.secondaryPersistentID == 0 })
    }

    @Test("a track that has the second copy stays untouched")
    func leavesHealthyTracksAlone() throws {
        let healthy = try LibraryFixture.standard().mappingTracks { $0.restoringSecondaryPersistentID() }
        let again = healthy.repairingSecondaryIdentifiers()
        #expect(again.repaired.isEmpty)
    }

    // MARK: - Album record identity

    @Test("an album record does not get a track identifier")
    func albumIdentityIsSeparate() throws {
        let library = try LibraryFixture.standard()
        // This is what the defect looked like: the caller passes a constant generator, so the track
        // and the album record get the same value.
        let constant: UInt64 = 0x1234_5678_9ABC_DEF0
        let after = try library.addingTracks([TrackDraft(title: "New", album: "Brand New Album",
                                                         sizeBytes: 1000, bitRate: 256, sampleRate: 44_100,
                                                         kind: .mp3, relativePath: "iPod_Control/Music/F01/AAAA.mp3")],
                                             persistentID: { constant })
        let album = try #require(after.albums.first { $0.title == "Brand New Album" })
        let track = try #require(after.tracks.first { $0.title == "New" })

        #expect(track.persistentID == constant)
        #expect(album.persistentID != track.persistentID,
                "this is the defect that put the artwork only on the album's first track")
        #expect(ITLibrary.isAlbumIdentity(album.persistentID),
                "the album record must live in the 0x2/0x102 space, like 116 of 118 records on the device")
    }

    @Test("the repair replaces an identifier colliding with a track")
    func repairsCollidingIdentity() throws {
        let library = try LibraryFixture.standard()
        let victim = try #require(library.tracks.first)
        let broken = library.mappingAlbums { album in
            var copy = album
            if album.title == victim.album { copy.persistentID = victim.persistentID }
            return copy
        }
        let outcome = broken.repairingAlbumIdentities(random: { 4242 })

        #expect(outcome.repaired.contains(victim.album ?? ""))
        let fixed = try #require(outcome.library.albums.first { $0.title == victim.album })
        #expect(fixed.persistentID != victim.persistentID)
        #expect(ITLibrary.isAlbumIdentity(fixed.persistentID))
        // No album record may carry a track identifier.
        let trackIDs = Set(outcome.library.tracks.map(\.persistentID))
        #expect(outcome.library.albums.allSatisfy { !trackIDs.contains($0.persistentID) })
    }

    @Test("a healthy library passes the repair unchanged")
    func healthyLibraryUntouched() throws {
        let library = try LibraryFixture.standard()
        let normalised = library.mappingAlbums { album in
            var copy = album
            copy.persistentID = ITLibrary.albumIdentitySpace | UInt64(album.index + 1)
            return copy
        }
        #expect(normalised.repairingAlbumIdentities().repaired.isEmpty)
    }

    @Test("the repair does not touch the album number the track finds it by")
    func keepsAlbumIndex() throws {
        let library = try LibraryFixture.standard()
        let victim = try #require(library.tracks.first)
        let broken = library.mappingAlbums { album in
            var copy = album
            if album.title == victim.album { copy.persistentID = victim.persistentID }
            return copy
        }
        let outcome = broken.repairingAlbumIdentities()
        for album in outcome.library.albums {
            let before = try #require(broken.albums.first { $0.title == album.title })
            #expect(album.index == before.index)
        }
        for track in outcome.library.tracks {
            let before = try #require(broken.tracks.first { $0.uniqueID == track.uniqueID })
            #expect(track.albumRecordIndex == before.albumRecordIndex)
        }
    }
}
