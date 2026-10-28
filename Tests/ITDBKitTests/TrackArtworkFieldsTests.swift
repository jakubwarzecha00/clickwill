import Testing
import Foundation
@testable import ITDBKit

/// The marker at 0x7E got lost silently: the record was correct in every other
/// field, the album showed artwork in Cover Flow, and not for the song
/// playing. Nothing in the app saw it, because nothing
/// read it - that is why the field now has its own tests.
@Suite("Track artwork fields")
struct TrackArtworkFieldsTests {

    /// A track from the fixture with the artwork fields set by hand.
    private func track(count: UInt16, marker: UInt16, size: UInt32 = 0) throws -> ITTrack {
        var track = try #require(LibraryFixture.standard().tracks.first)
        track.rawHeader[0x7C] = UInt8(count & 0xFF); track.rawHeader[0x7D] = UInt8(count >> 8)
        track.rawHeader[0x7E] = UInt8(marker & 0xFF); track.rawHeader[0x7F] = UInt8(marker >> 8)
        for i in 0..<4 { track.rawHeader[0x80 + i] = UInt8((size >> (8 * UInt32(i))) & 0xFF) }
        track.embeddedArtworkCount = count
        track.embeddedArtworkSize = size
        return track
    }

    @Test("the marker is recognized even with a zero count")
    func detection() throws {
        let withCover = try track(count: 1, marker: 0xFFFF)
        let withoutCover = try track(count: 0, marker: 0xFFFF)
        let broken = try track(count: 1, marker: 0x0000)
        #expect(withCover.hasArtworkMarker)
        #expect(withoutCover.hasArtworkMarker, "iTunes sets the marker whether or not there is artwork")
        #expect(broken.hasArtworkMarker == false)
    }

    @Test("marking artwork writes three fields and reaches no further")
    func marking() throws {
        let before = try track(count: 0, marker: 0x0000)
        let after = before.markingArtwork(imageSourceByteCount: 125_547, count: 1)

        #expect(after.embeddedArtworkCount == 1)
        #expect(after.embeddedArtworkSize == 125_546, "0x80 is the source size minus the count")
        #expect(after.hasArtworkMarker)
        // The heart of the defect: the count is sixteen bits, so the write must not
        // reach 0x7E. A four-byte zero at 0x7C wiped the marker.
        #expect(after.rawHeader[0x7C] == 1 && after.rawHeader[0x7D] == 0)
        #expect(after.pointsAtImage(sourceByteCount: 125_547))
        #expect(after.rawHeader[0x7B] == before.rawHeader[0x7B])
        #expect(after.rawHeader[0x84] == before.rawHeader[0x84])
    }

    @Test("the repair gives back the marker and does not invent a count")
    func repairKeepsCounts() throws {
        let fixed = try track(count: 2, marker: 0x0000, size: 4242).restoringArtworkMarker()
        #expect(fixed.hasArtworkMarker)
        #expect(fixed.embeddedArtworkCount == 2, "a marker repair is not the place to guess a count")
        #expect(fixed.embeddedArtworkSize == 4242)
    }

    @Test("a healthy record passes through the repair unchanged")
    func repairIsIdempotent() throws {
        let healthy = try track(count: 1, marker: 0xFFFF, size: 99)
        #expect(healthy.restoringArtworkMarker().rawHeader == healthy.rawHeader)
    }

    @Test("the library repair counts only broken records")
    func libraryRepair() throws {
        var library = try LibraryFixture.standard()
        library = library.mappingTracks { track in
            var copy = track
            copy.rawHeader[0x7E] = 0xFF; copy.rawHeader[0x7F] = 0xFF
            return copy
        }
        #expect(library.repairingArtworkMarkers().repaired == 0)

        // We break one record the way the generator broke it.
        let broken = library.mappingTracks { track in
            guard track.uniqueID == library.tracks[0].uniqueID else { return track }
            var copy = track
            copy.rawHeader[0x7E] = 0; copy.rawHeader[0x7F] = 0
            return copy
        }
        let outcome = broken.repairingArtworkMarkers()
        #expect(outcome.repaired == 1)
        #expect(outcome.library.tracks.allSatisfy { $0.hasArtworkMarker })
    }

    @Test("a newly inserted track has the marker right away")
    func insertionKeepsMarker() throws {
        let library = try LibraryFixture.standard()
        let draft = TrackDraft(title: "New Song", album: "Currents", sizeBytes: 5_000_000,
                               bitRate: 256, sampleRate: 44_100, kind: .mp3,
                               relativePath: "iPod_Control/Music/F07/ZZZZ.mp3")
        let after = try library.addingTracks([draft])
        let added = try #require(after.tracks.last)

        #expect(added.hasArtworkMarker, "this is the regression that let out 38 records without artwork for the song")
        #expect(added.embeddedArtworkCount == 0, "a new track does not inherit the artwork count from the template")
        #expect(added.embeddedArtworkSize == 0)
    }

    @Test("marking an album covers all its tracks")
    func albumWide() throws {
        let library = try LibraryFixture.standard()
        let album = try #require(library.tracks.first?.album)
        let marked = library.markingAlbumArtwork(album: album, sourceByteCount: 4242)

        let inAlbum = marked.tracks.filter { $0.album == album }
        #expect(inAlbum.count > 1)
        #expect(inAlbum.allSatisfy { $0.embeddedArtworkCount == 1 && $0.embeddedArtworkSize == 4241 },
                "album artwork applies to every song, not just the owner of the image record")
        #expect(marked.tracks.filter { $0.album != album }.allSatisfy { $0.embeddedArtworkSize != 4241 })
    }
}

/// The rule linking a track record to an image record, measured on the device:
/// `mhii` 0x30 = track 0x80 + track 0x7C. A track that does not satisfy this rule
/// points to an image that is not in the database.
@Suite("Track pointer to artwork")
struct ArtworkSourceRuleTests {

    private func library() throws -> ITLibrary { try LibraryFixture.standard() }

    @Test("the declared size is the source size minus the count")
    func rule() {
        #expect(ITTrack.declaredSize(forImageSource: 65_608, count: 1) == 65_607)
        #expect(ITTrack.declaredSize(forImageSource: 227_343, count: 2) == 227_341)
        // Measured on the device: Blizzard of Ozz and the second record of "The Tourist".
        #expect(ITTrack.declaredSize(forImageSource: 3, count: 5) == 0, "we do not go below zero")
    }

    @Test("marking an album satisfies the rule")
    func markingFollowsRule() throws {
        let album = try #require(library().tracks.first?.album)
        let marked = try library().markingAlbumArtwork(album: album, sourceByteCount: 227_343)
        for track in marked.tracks where track.album == album {
            #expect(track.pointsAtImage(sourceByteCount: 227_343))
            #expect(track.embeddedArtworkCount == 1)
            #expect(track.embeddedArtworkSize == 227_342)
        }
    }

    @Test("the repair moves the pointer to an image that exists")
    func repairsDanglingReference() throws {
        let album = try #require(library().tracks.first?.album)
        // This is what "Ok Computer" looks like: the tracks point to 125546, and the album's image
        // has a source size of 227343.
        let broken = try library().mappingTracks { track in
            guard track.album == album else { return track }
            return track.markingArtwork(imageSourceByteCount: 125_547, count: 1)
        }
        let outcome = broken.repairingArtworkSources(imageSourcesByAlbum: [album: 227_343])

        #expect(outcome.repaired[album] == broken.tracks.count { $0.album == album })
        for track in outcome.library.tracks where track.album == album {
            #expect(track.pointsAtImage(sourceByteCount: 227_343))
        }
        // Tracks of other albums untouched.
        for track in outcome.library.tracks where track.album != album {
            let before = try #require(broken.tracks.first { $0.uniqueID == track.uniqueID })
            #expect(track.embeddedArtworkSize == before.embeddedArtworkSize)
        }
    }

    @Test("a track pointing to an existing image stays untouched")
    func leavesValidReferences() throws {
        let album = try #require(library().tracks.first?.album)
        let healthy = try library().markingAlbumArtwork(album: album, sourceByteCount: 227_343)
        let outcome = healthy.repairingArtworkSources(imageSourcesByAlbum: [album: 227_343])
        #expect(outcome.repaired.isEmpty)
    }

    @Test("an album without an image is not touched")
    func skipsAlbumsWithoutImage() throws {
        let outcome = try library().repairingArtworkSources(imageSourcesByAlbum: [:])
        #expect(outcome.repaired.isEmpty, "there is nothing to repair and nothing to guess from")
    }
}
