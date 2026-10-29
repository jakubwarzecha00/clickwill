import Testing
import Foundation
@testable import ITDBKit

/// Field 0x160 - the track's pointer to an image record. This is the path the iPod
/// takes to the artwork during playback (the other artwork fields are not), so it
/// has its own tests.
@Suite("Track pointer to an image record")
struct TrackArtworkIdentifierTests {

    private func library() throws -> ITLibrary { try LibraryFixture.standard() }

    private func track(identifier: UInt32) throws -> ITTrack {
        let base = try #require(library().tracks.first)
        return base.settingArtworkIdentifier(identifier)
    }

    @Test("writing and reading are symmetric")
    func roundTrip() throws {
        #expect(try track(identifier: 265).artworkIdentifier == 265)
        #expect(try track(identifier: 0).artworkIdentifier == 0)
        #expect(try track(identifier: .max).artworkIdentifier == .max)
    }

    @Test("the write reaches no further than its four bytes and byte 0xA4")
    func staysInBounds() throws {
        let before = try #require(library().tracks.first)
        let after = before.settingArtworkIdentifier(0xFFFF_FFFF)
        for i in 0..<before.rawHeader.count where !(0x160..<0x164).contains(i) && i != 0xA4 {
            #expect(after.rawHeader[i] == before.rawHeader[i], "touched byte \(String(i, radix: 16))")
        }
    }

    @Test("0xA4 goes together with 0x160: 1 with an image, 2 without - as in Apple's records")
    func presenceFollowsIdentifier() throws {
        #expect(try track(identifier: 265).artworkPresence == 1)
        #expect(try track(identifier: 0).artworkPresence == 2)
    }

    @Test("the repair fills in zero and counts only the tracks touched")
    func fillsMissing() throws {
        let album = try #require(library().tracks.first?.album)
        let broken = try library().mappingTracks { track in
            (track.album ?? "") == album ? track.settingArtworkIdentifier(0) : track
        }
        let outcome = broken.repairingArtworkIdentifiers(
            imageIdentifiersByAlbum: [album: 265], existingIdentifiers: [265])

        let inAlbum = outcome.library.tracks.filter { ($0.album ?? "") == album }
        #expect(inAlbum.count > 1)
        #expect(inAlbum.allSatisfy { $0.artworkIdentifier == 265 })
        #expect(outcome.repaired[album] == inAlbum.count)
    }

    @Test("a pointer to an existing image stays untouched")
    func keepsValidPointers() throws {
        // Measured: there are albums using several records at once ("I AM MUSIC"
        // 112, 113 and 240). Overwriting them with one value would put someone else's
        // artwork under a song.
        let album = try #require(library().tracks.first?.album)
        let mixed = try library().mappingTracks { track in
            guard (track.album ?? "") == album else { return track }
            return track.settingArtworkIdentifier(track.trackNumber == 1 ? 240 : 0)
        }
        let outcome = mixed.repairingArtworkIdentifiers(
            imageIdentifiersByAlbum: [album: 112], existingIdentifiers: [112, 240])

        let odd = outcome.library.tracks.first { ($0.album ?? "") == album && $0.trackNumber == 1 }
        #expect(odd?.artworkIdentifier == 240, "a pointer that leads to an existing image is not an error")
        #expect(outcome.repaired[album] == mixed.tracks.count { ($0.album ?? "") == album } - 1)
    }

    @Test("a dangling pointer is repaired the same way as zero")
    func repairsDangling() throws {
        let album = try #require(library().tracks.first?.album)
        let broken = try library().mappingTracks { track in
            (track.album ?? "") == album ? track.settingArtworkIdentifier(9999) : track
        }
        let outcome = broken.repairingArtworkIdentifiers(
            imageIdentifiersByAlbum: [album: 265], existingIdentifiers: [265])
        #expect(outcome.library.tracks.filter { ($0.album ?? "") == album }.allSatisfy { $0.artworkIdentifier == 265 })
    }

    @Test("an album without an unambiguous image is not touched")
    func skipsUnknownAlbums() throws {
        let outcome = try library().repairingArtworkIdentifiers(
            imageIdentifiersByAlbum: [:], existingIdentifiers: [265])
        #expect(outcome.repaired.isEmpty, "there is nothing to point to and nothing to guess from")
    }

    @Test("a new track does not inherit the pointer from the template")
    func insertionClearsInheritedPointer() throws {
        // A template with someone else's image: if the record took it over, the new song
        // would show another album's artwork.
        let base = try library()
        let seeded = base.mappingTracks { $0.settingArtworkIdentifier(130) }
        let draft = TrackDraft(title: "New Song", album: "Currents", sizeBytes: 5_000_000,
                               bitRate: 256, sampleRate: 44_100, kind: .mp3,
                               relativePath: "iPod_Control/Music/F07/ZZZZ.mp3")
        let added = try #require(try seeded.addingTracks([draft]).tracks.last)
        #expect(added.artworkIdentifier == 0, "this is a pointer to another album's artwork")
        #expect(added.artworkPresence == 2, "no image, although the template had 1")
    }

    @Test("an album with two different pictures gets no pointer - no guessing")
    func differentPicturesGiveNoPointer() throws {
        let library = try library()
        let bends = library.tracks.filter { $0.album == "The Bends" }
        let artwork = try ArtworkDBParser.parse(ArtworkCoverageTests.artworkDB(
            owner: bends[0].persistentID, declared: 1, extra: (owner: bends[1].persistentID, declared: 1)))

        #expect(artwork.imageIdentifiersByAlbum(in: library)["The Bends"] == nil)
    }
}
