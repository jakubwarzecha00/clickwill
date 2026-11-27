import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The movie list computed from the library. The synthetic database has only songs;
/// the tests mark some of them with a media kind.
@Suite("Video catalog")
struct VideoCatalogTests {

    private func library(kinds: [String: UInt32]) throws -> ITLibrary {
        try ITunesDBParser.parse(SyntheticLibrary.database()).mappingTracks { track in
            guard let kind = kinds[track.title ?? ""] else { return track }
            var marked = track
            marked.rawHeader.set(MhitLayout.mediaKind, kind)
            return marked
        }
    }

    @Test("songs alone give no movies")
    func songsOnly() throws {
        let catalog = VideoCatalog(library: try library(kinds: ["Bones": 1]))
        #expect(catalog.movies.isEmpty)
    }

    @Test("a movie is listed with its title, length and size, in database order")
    func movies() throws {
        let library = try library(kinds: ["Eventually": 2, "Bones": 2])
        let catalog = VideoCatalog(library: library)
        #expect(catalog.movies.map(\.title) == ["Bones", "Eventually"])
        let eventually = try #require(library.tracks.first { $0.title == "Eventually" })
        let row = try #require(catalog.movies.last)
        #expect(row.id == eventually.uniqueID)
        #expect(row.duration == eventually.duration)
        #expect(row.sizeBytes == Int64(eventually.sizeBytes))
        #expect(catalog.unrecognizedCount == 0)
    }

    @Test("only the measured movie kind counts")
    func unmeasuredKindsLeftOut() throws {
        // 0x03: the audio bit wins, so it stays a song. 0x08 and 0x40 are not measured.
        let catalog = VideoCatalog(library: try library(kinds: ["Bones": 3, "Just": 8, "Let It Happen": 0x40]))
        #expect(catalog.movies.isEmpty)
        // Neither music nor a movie: counted, so the TV Shows and Podcasts pages never claim "none".
        #expect(catalog.unrecognizedCount == 2)
    }

    @Test("a movie without a title gets a placeholder")
    func untitled() throws {
        let library = try ITunesDBParser.parse(SyntheticLibrary.database(titles: [16: ""])).mappingTracks { track in
            guard track.uniqueID == 16 else { return track }
            var movie = track
            movie.rawHeader.set(MhitLayout.mediaKind, UInt32(2))
            return movie
        }
        let row = try #require(VideoCatalog(library: library).movies.first)
        #expect(row.displayTitle == "Untitled Movie")
    }
}
