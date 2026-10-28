import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

/// The Albums tab: the order and letters as in the Albums menu on the iPod.
@Suite("Albums menu")
@MainActor
struct AlbumsMenuTests {

    @Test("the order as in the iPod's Albums menu - The Bends under B")
    func deviceOrder() async throws {
        let model = try await AdditionsTests.model()
        #expect(model.albumsDisplay.map(\.title) == ["Aftermath", "The Bends", "Currents"])
    }

    @Test("the letter without a leading The - The Bends under B, not under T")
    func letters() async throws {
        let model = try await AdditionsTests.model()
        #expect(model.albumsDisplay.map(model.menuLetter(of:)) == ["A", "B", "C"])
    }

    @Test("an album from the queue stands in its place in the alphabet in the menu")
    func pendingAlbumsInMenuOrder() async throws {
        // The catalog lives until the end of the test - Discard All reloads the library.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("menu-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let model = LibraryModel()
        await model.load(.snapshot(root))
        model.queueAdditions([AdditionsTests.candidate(title: "Soon", album: "Loveless", file: "1.mp3"),
                              AdditionsTests.candidate(title: "Only Shallow", album: "Glider", file: "2.mp3"),
                              AdditionsTests.candidate(title: "Zeta", album: "Zeta", file: "3.mp3")])

        #expect(model.albumsDisplay.map(\.title) == ["Aftermath", "The Bends", "Currents", "Glider", "Loveless", "Zeta"])
        #expect(model.albums.map(\.title) == ["Aftermath", "The Bends", "Currents"])
        let pending = model.albumsDisplay.filter(\.isPending)
        #expect(pending.map(model.menuLetter(of:)) == ["G", "L", "Z"])

        await model.discardChanges()
        #expect(model.albumsDisplay.map(\.title) == ["Aftermath", "The Bends", "Currents"])
    }

    @Test("album facts: format, size, parts; an album from the queue - files from the Mac")
    func facts() async throws {
        let model = try await AdditionsTests.model()
        let aftermath = try #require(model.albumsDisplay.first { $0.title == "Aftermath" })
        let onDevice = model.facts(of: aftermath)
        #expect(onDevice.format == "MP3")
        #expect(onDevice.unplayable == 0 && onDevice.convertsTo == nil)
        #expect(!aftermath.hasArtwork)

        model.queueAdditions([AdditionsTests.candidate(title: "Soon", album: "Glider", file: "1.mp3"),
                              AdditionsTests.candidate(title: "Only Shallow", album: "Glider", file: "2.mp3")])
        let glider = try #require(model.albumsDisplay.first { $0.title == "Glider" })
        let pending = model.facts(of: glider)
        #expect(pending.format == "MP3 44.1 kHz 256 kbps")
        #expect(pending.bytes == 8_000_000)
    }

    @Test("the Albums menu rule from readings on a classic")
    func deviceRule() {
        func card(_ title: String, sort: String? = nil) -> AlbumCard {
            var card = AlbumCard(id: .pending(AlbumKey(album: title, albumArtist: "X")), trackIndices: [], trackIDs: [],
                                 title: title, artist: "X", year: nil, genre: nil, trackCount: 1, duration: 0,
                                 artworkTrackID: nil, missingFiles: 0, isCompilation: false, artistSortKey: "X")
            card.albumSortName = sort
            return card
        }
        // The order read from the device (Music > Albums).
        let device = ["beerbongs & bentleys", "The Bends", "The Best of Jimi Hendrix", "Brothers In Arms", "…But Seriously",
                      "CALL ME IF YOU GET LOST", "Madvillainy", "Metallica", "MM...FOOD", "Moody Blue", "Yeezus",
                      "ダンシング・ヒーロー -ALL EAT YOU UP-", "4X4", "808s & Heartbreak", ""]
        let sortNames = ["The Bends": "Bends", "The Best of Jimi Hendrix": "Best of Jimi Hendrix"]
        let shuffled = device.reversed().map { card($0, sort: sortNames[$0]) }
        #expect(AlbumsMenu.order(shuffled).map(\.title) == device)
        #expect(AlbumsMenu.order(shuffled).map(AlbumsMenu.letter(of:))
                == ["B", "B", "B", "B", "B", "C", "M", "M", "M", "M", "Y", "#", "#", "#", ""])
    }

    @Test("Cover Flow only on generations that have it")
    func coverFlowGenerations() {
        let with = IPodCatalog.Generation.allCases.filter(\.hasCoverFlow)
        #expect(with == [.classic1, .classic2, .classic3, .nano3, .nano4, .nano5])
    }

    @Test("without a known generation Cover Flow stays")
    func unknownGenerationKeepsCoverFlow() async throws {
        let model = try await AdditionsTests.model()
        #expect(model.device == nil)
        #expect(model.hasCoverFlow)
    }
}
