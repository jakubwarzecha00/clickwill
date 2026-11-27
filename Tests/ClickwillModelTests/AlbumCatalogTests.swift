import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The card catalog computed directly from the library, without the model and without a disk.
/// The synthetic database: Aftermath (Rolling Stones), The Bends (Radiohead),
/// Currents (Tame Impala).
@Suite("Album catalog")
struct AlbumCatalogTests {

    private func library() throws -> ITLibrary { try ITunesDBParser.parse(SyntheticLibrary.database()) }

    @Test("albums in table order, the strip in iPod order")
    func twoOrders() throws {
        let catalog = AlbumCatalog(library: try library(), artwork: nil, missingFiles: [])
        #expect(catalog.albums.map(\.title) == ["Aftermath", "The Bends", "Currents"])
        #expect(catalog.coverFlow.map(\.title) == ["The Bends", "Aftermath", "Currents"])
        // A strip card covering a whole block is the same card as in the table.
        for card in catalog.coverFlow { #expect(catalog.current(card) == card) }
    }

    @Test("the compilation flag from the track field moves the album to the end of the strip")
    func compilationFromTrackField() throws {
        let library = try library().mappingTracks { track in
            guard track.album == "The Bends" else { return track }
            var flagged = track
            flagged.isCompilation = true
            return flagged
        }
        let catalog = AlbumCatalog(library: library, artwork: nil, missingFiles: [])
        let bends = try #require(catalog.albums.first { $0.title == "The Bends" })
        #expect(bends.isCompilation)
        #expect(catalog.coverFlow.map(\.title) == ["Aftermath", "Currents", "The Bends"])
    }

    @Test("the missing files counter on the card")
    func missingFiles() throws {
        let library = try library()
        let currents = library.tracks.filter { $0.album == "Currents" }.map(\.uniqueID)
        let catalog = AlbumCatalog(library: library, artwork: nil, missingFiles: [try #require(currents.first)])
        #expect(catalog.albums.map(\.missingFiles) == [0, 0, 1])
    }

    @Test("a movie gets no card and leaves the songs of its block alone")
    func moviesHidden() throws {
        let library = try library().mappingTracks { track in
            guard track.album == "Aftermath" || track.title == "Eventually" else { return track }
            var movie = track
            movie.rawHeader.set(MhitLayout.mediaKind, UInt32(2))
            return movie
        }
        let catalog = AlbumCatalog(library: library, artwork: nil, missingFiles: [])
        #expect(catalog.albums.map(\.title) == ["The Bends", "Currents"])
        #expect(catalog.coverFlow.map(\.title) == ["The Bends", "Currents"])
        let currents = try #require(catalog.albums.last)
        #expect(currents.trackCount == 1)
        #expect(currents.trackIndices.allSatisfy { library.tracks[$0].isMusic })
    }

    @Test("an empty catalog has no cards")
    func empty() {
        #expect(AlbumCatalog.empty.albums.isEmpty && AlbumCatalog.empty.coverFlow.isEmpty)
    }
}
