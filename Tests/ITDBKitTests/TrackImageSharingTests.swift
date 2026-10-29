import Foundation
import Testing
@testable import ITDBKit

/// Which tracks get their own image record on an iPod that finds artwork by the track.
/// The artwork databases come from `ArtworkCoverageTests`: image 101 at offset 0,
/// image 102 at offset 204800 - two different pictures.
@Suite("Image records per track")
struct TrackImageSharingTests {

    @Test("an album with one picture: the other songs share it")
    func onePictureIsShared() throws {
        let library = try LibraryFixture.standard()
        let owner = try ArtworkCoverageTests.owner(of: "The Bends", in: library)
        let artwork = try ArtworkDBParser.parse(ArtworkCoverageTests.artworkDB(owner: owner, declared: 1))

        let shares = artwork.trackImageShares(in: library)

        let bends = library.tracks.filter { $0.album == "The Bends" }.map(\.persistentID)
        #expect(shares == [TrackImageShare(album: "The Bends", imageID: 101, tracks: bends.filter { $0 != owner })])
    }

    @Test("an album with two different pictures is left alone - no guessing")
    func differentPicturesAreLeftAlone() throws {
        let library = try LibraryFixture.standard()
        let bends = library.tracks.filter { $0.album == "The Bends" }
        let artwork = try ArtworkDBParser.parse(ArtworkCoverageTests.artworkDB(
            owner: bends[0].persistentID, declared: 1, extra: (owner: bends[1].persistentID, declared: 1)))

        #expect(artwork.trackImageShares(in: library).isEmpty)
    }

    @Test("albums without artwork and albums where every song has a record give nothing")
    func nothingToShare() throws {
        let library = try LibraryFixture.standard()
        let currents = library.tracks.filter { $0.album == "Currents" }
        #expect(currents.count == 2)
        let artwork = try ArtworkDBParser.parse(ArtworkCoverageTests.artworkDB(
            owner: currents[0].persistentID, declared: 1, extra: (owner: currents[1].persistentID, declared: 1)))
        // Two records, but different slices: still not one picture - and no song is missing one anyway.
        #expect(artwork.trackImageShares(in: library).isEmpty)
    }
}
