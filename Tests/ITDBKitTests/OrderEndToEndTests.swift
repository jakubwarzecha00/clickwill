import Foundation
import Testing
@testable import ITDBKit

@Suite("Order - synthetic database")
struct OrderEndToEndTests {

    @Test("the fixture parses, reproduces byte for byte and gives three blocks")
    func fixtureRoundTrips() throws {
        let data = LibraryFixture.database(
            tracks: LibraryFixture.tracks, albumOrder: LibraryFixture.alphabeticalOrder,
            jump: LibraryFixture.alphabeticalJump)
        let library = try ITunesDBParser.parse(data)
        #expect(ITunesDBWriter.serialize(library) == data)
        #expect(library.albumOrder().map(\.album) == ["Aftermath", "The Bends", "Currents"])
        #expect(library.jumpTable(.album)?.entries.count == 3)
    }

    @Test("the bar computed from the layout reproduces the fixture's bar")
    func derivedJumpMatches() throws {
        let library = try LibraryFixture.standard()
        let stored = try #require(library.jumpTable(.album))
        let derived = stored.rebuilt(fromRuns: library.albumOrder().map { (library.albumLetterCode($0), $0.trackCount) })
        #expect(derived.mhod().rawBody == stored.mhod().rawBody)
    }

    @Test("moving an album across letter boundaries rebuilds the bar in both copies")
    func crossLetterMove() throws {
        let library = try LibraryFixture.standard()
        let moved = try library.movingAlbum("Currents", .atIndex(0))

        #expect(moved.albumOrder().map(\.album) == ["Currents", "Aftermath", "The Bends"])
        let jump = try #require(moved.jumpTable(.album))
        #expect(jump.entries.map { [$0.letter, $0.start, $0.count] } == [[67, 0, 2], [65, 2, 2], [66, 4, 3]])

        // Both sections with a playlist must carry the same table and bar.
        var bodies: Set<[UInt8]> = []
        for section in moved.sections {
            guard case .playlists(let playlists) = section.content else { continue }
            for mhod in playlists[0].mhods where mhod.type == .libraryPlaylistIndex || mhod.type == .libraryPlaylistJumpTable {
                bodies.insert(mhod.rawBody)
            }
        }
        #expect(bodies.count == 2)   // one table + one bar, identical in both copies

        // The result passes through the writer and the parser unchanged.
        let again = try ITunesDBParser.parse(ITunesDBWriter.serialize(moved))
        #expect(again.albumOrder().map(\.album) == ["Currents", "Aftermath", "The Bends"])
    }

    @Test("a flattened bar is one entry for the whole table")
    func flatPolicy() throws {
        let moved = try LibraryFixture.standard().movingAlbum("Currents", .atIndex(0), jumpTable: .flat)
        let jump = try #require(moved.jumpTable(.album))
        #expect(jump.entries.count == 1)
        #expect(jump.entries[0].count == 7)
    }

    @Test("moving a track permutes only the album's block, the bar unchanged")
    func trackMove() throws {
        let library = try LibraryFixture.standard()
        let before = try #require(library.jumpTable(.album)).mhod().rawBody
        let moved = try library.movingTrack(14, in: "The Bends", .atIndex(0))   // Just to the start

        #expect(try moved.trackOrder(album: "The Bends").map(\.title) == ["Just", "Planet Telex", "Bones"])
        #expect(try moved.trackOrder(album: "Aftermath").map(\.title) == ["Paint It Black", "Let Me Down"])
        #expect(try #require(moved.jumpTable(.album)).mhod().rawBody == before)
    }

    @Test("renumbering follows the layout, not the old numbers")
    func renumber() throws {
        let moved = try LibraryFixture.standard()
            .movingTrack(14, in: "The Bends", .atIndex(0))
            .renumberingTracks(album: "The Bends")
        let numbers = try moved.trackOrder(album: "The Bends").map { ($0.title, $0.trackNumber, $0.totalTracks) }
        #expect(numbers.map(\.1) == [1, 2, 3])
        #expect(numbers.map(\.2) == [3, 3, 3])
        #expect(numbers.map(\.0) == ["Just", "Planet Telex", "Bones"])
        // Other albums untouched.
        #expect(try moved.trackOrder(album: "Aftermath").map(\.trackNumber) == [1, 2])
    }

    @Test("the new order must be the same set of tracks")
    func rejectsWrongSet() throws {
        let library = try LibraryFixture.standard()
        #expect(throws: TrackOrderError.self) {
            _ = try library.settingTrackOrder(album: "The Bends", uniqueIDs: [10, 12])
        }
        #expect(throws: TrackOrderError.self) {
            _ = try library.settingTrackOrder(album: "The Bends", uniqueIDs: [10, 12, 15])
        }
    }

    @Test("removing a track remaps the table and the bar across the database")
    func removalEndToEnd() throws {
        let library = try LibraryFixture.standard()
        let removed = try library.removingTracks(uniqueIDs: [12])   // Planet Telex

        #expect(removed.tracks.count == 6)
        let index = try #require(removed.browseIndex(.album))
        #expect(index.isPermutation(of: 6))
        #expect(removed.albumOrder().map { ($0.album, $0.trackCount) }.map { [$0.0, String($0.1)] }
                == [["Aftermath", "2"], ["The Bends", "2"], ["Currents", "2"]])
        let jump = try #require(removed.jumpTable(.album))
        #expect(jump.entries.map { [$0.letter, $0.start, $0.count] } == [[65, 0, 2], [66, 2, 2], [67, 4, 2]])
        for section in removed.sections {
            guard case .playlists(let playlists) = section.content else { continue }
            #expect(playlists[0].entries.count == 6)
            #expect(!playlists[0].entries.contains { $0.trackID == 12 })
        }
        _ = try ITunesDBParser.parse(ITunesDBWriter.serialize(removed))
    }
}
