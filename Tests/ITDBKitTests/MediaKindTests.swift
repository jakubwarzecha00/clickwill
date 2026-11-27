import Foundation
import Testing
@testable import ITDBKit

/// A movie added by Finder lives in the same track list as the songs, and on an
/// iPod classic it sits in the album table with the untitled songs. It must survive
/// every write exactly as Apple left it: repairs and album edits measured on songs
/// must not reach it.
@Suite("Media kind")
struct MediaKindTests {

    /// The standard albums plus a movie (id 17) inside the block of The Bends.
    /// The movie is described as AAC on purpose, so that only its media kind keeps
    /// it out of the template choice. Track 10 carries an explicit media kind 1.
    private func library() throws -> ITLibrary {
        var tracks = LibraryFixture.tracks
        tracks[0].mediaKind = 1
        tracks.append(.init(id: 17, title: "Clip", album: "The Bends", artist: "Radiohead", number: 0,
                            kind: .aac, mediaKind: 2))
        let order: [UInt32] = [3, 1, 2, 0, 7, 4, 5, 6]
        let jump: [(UInt32, UInt32, UInt32)] = [(65, 0, 2), (66, 2, 4), (67, 6, 2)]
        return try ITunesDBParser.parse(LibraryFixture.database(tracks: tracks, albumOrder: order, jump: jump))
    }

    private func movie(in library: ITLibrary) throws -> ITTrack {
        try #require(library.tracks.first { $0.uniqueID == 17 })
    }

    @Test("zero and the audio bit count as music, a movie does not")
    func classification() throws {
        let library = try library()
        #expect(try movie(in: library).mediaKind == 2)
        #expect(try movie(in: library).isMusic == false)
        #expect(library.tracks.first { $0.uniqueID == 10 }?.mediaKind == 1)
        #expect(library.tracks.filter { !$0.isMusic }.map(\.uniqueID) == [17])
        #expect(library.musicTracks.map(\.uniqueID).contains(17) == false)
    }

    @Test("the writer keeps the media kind")
    func roundTrip() throws {
        let again = try ITunesDBParser.parse(ITunesDBWriter.serialize(try library()))
        #expect(try movie(in: again).mediaKind == 2)
    }

    @Test("repairs that run on every write leave a movie byte for byte")
    func repairsSkipMovie() throws {
        // One song with the second identifier, so that the repair runs at all.
        var library = try library().mappingTracks { $0.uniqueID == 10 ? $0.restoringSecondaryPersistentID() : $0 }
        let before = try movie(in: library).rawHeader

        library = library.repairingArtworkMarkers().library
        library = library.repairingSecondaryIdentifiers().library
        library = library.repairingArtworkIdentifiers(imageIdentifiersByAlbum: ["The Bends": 100],
                                                      existingIdentifiers: [100]).library
        library = library.repairingArtworkSources(imageSourcesByAlbum: ["The Bends": 4096]).library
        library = library.markingAlbumArtwork(album: "The Bends", sourceByteCount: 4096)

        #expect(try movie(in: library).rawHeader == before)
        let song = try #require(library.tracks.first { $0.uniqueID == 12 })
        #expect(song.hasArtworkMarker && song.secondaryPersistentID != 0 && song.artworkIdentifier == 100)
    }

    @Test("track order skips a movie and keeps its place in the table")
    func orderKeepsMovieSlot() throws {
        let library = try library()
        #expect(try library.trackOrder(album: "The Bends").map(\.uniqueID) == [12, 10, 14])

        let moved = try library.movingTrack(14, in: "The Bends", .atIndex(0))
        #expect(try moved.trackOrder(album: "The Bends").map(\.uniqueID) == [14, 12, 10])
        let block = try #require(moved.albumOrder().first { $0.album == "The Bends" })
        #expect(block.trackIndices == [4, 2, 7, 0], "the movie (index 7) stays third in the block")

        let renumbered = try moved.renumberingTracks(album: "The Bends")
        #expect(try trackNumbers(renumbered) == [14: 1, 12: 2, 10: 3])
        let original = try movie(in: library).rawHeader
        #expect(try movie(in: renumbered).rawHeader == original)
    }

    @Test("a movie is never a template for a new song")
    func noMovieTemplate() throws {
        #expect(try library().templateTrack(for: .aac) == nil)
    }

    private func trackNumbers(_ library: ITLibrary) throws -> [UInt32: UInt32] {
        let songs = try library.trackOrder(album: "The Bends")
        return Dictionary(uniqueKeysWithValues: songs.map { ($0.uniqueID, $0.trackNumber) })
    }
}
