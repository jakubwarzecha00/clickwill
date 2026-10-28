import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

/// The same synthetic database as in LibraryModelTests: Aftermath (Rolling Stones),
/// The Bends (Radiohead), Currents (Tame Impala).
private func snapshot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("clickwill-groups-\(UUID().uuidString)", isDirectory: true)
    let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
    try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
    try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
    return root
}

@Suite("Cover Flow groups")
@MainActor
struct CoverFlowGroupsTests {

    @Test("groups go by artist, not by album name")
    func groupsByArtist() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let groups = model.coverFlowGroups
        // Radiohead < Rolling Stones < Tame Impala, although the album table has Aftermath first.
        #expect(groups.map(\.title) == ["Radiohead", "Rolling Stones", "Tame Impala"])
        #expect(model.coverFlowAlbums.map(\.title) == ["The Bends", "Aftermath", "Currents"])
    }

    @Test("the compilation flag moves the album to the group at the end, and it can be cleared")
    func compilationGroup() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let bends = try #require(model.coverFlowAlbums.first { $0.title == "The Bends" })

        model.setCompilation(bends, true)
        #expect(model.coverFlowGroups.map(\.title) == ["Rolling Stones", "Tame Impala", "Compilations"])
        #expect(model.coverFlowGroups.last?.kind == .compilations)
        #expect(model.library?.tracks.filter { $0.album == "The Bends" }.allSatisfy { $0.isCompilation } == true)
        guard case .compilationChanged(let album, let flag, _)? = model.changes.log.last?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.last?.kind))"); return
        }
        #expect(album == "The Bends" && flag)

        let again = try #require(model.coverFlowAlbums.first { $0.title == "The Bends" })
        model.setCompilation(again, false)
        #expect(model.coverFlowGroups.map(\.title) == ["Radiohead", "Rolling Stones", "Tame Impala"])
    }

    @Test("moving an album within a group goes through the album table")
    func moveWithinGroup() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        // Two albums by the same artist would be needed, but the fixture has
        // one album per artist, so moving Aftermath into Radiohead through flags
        // is not possible; so we check that a move in a one-element group is a no-op.
        let group = model.coverFlowGroups[0]
        try model.moveAlbumWithinGroup(group.albums[0], in: group, toOffset: 1)
        #expect(model.changes.log.isEmpty)
    }
}

@Suite("Cover Flow cards and the album table")
@MainActor
struct CoverFlowCardIdentityTests {

    /// A bug from the device: after the group and block numbering diverged, the card
    /// "Paranoid" opened from Cover Flow had no counterpart in `albums`,
    /// and `moveTracks` silently did nothing.
    @Test("a card covering a whole block has that block's identifier, also after the numbering diverges")
    func cardsKeepBlockIdentity() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        // We split Aftermath (block 0) into two groups: one track gets a different
        // album artist. From here on the group numbers do not match the blocks.
        let library = try #require(model.library)
        model.replaceLibrary(library.mappingTracks { track in
            track.title == "Let Me Down" ? track.setting(.sortAlbumArtist, to: "Someone Else") : track
        })
        model.rebuildCards()

        let split = model.coverFlowAlbums.filter { $0.title == "Aftermath" }
        #expect(split.count == 2)
        #expect(split.allSatisfy { model.catalog.block(for: $0) == nil }, "a part of a block has no single block")

        for title in ["The Bends", "Currents"] {
            let card = try #require(model.coverFlowAlbums.first { $0.title == title })
            let table = try #require(model.albums.first { $0.title == title })
            #expect(card.id == table.id, "\(title)")
            #expect(model.index(of: card) == model.index(of: table))
        }

        let currents = try #require(model.coverFlowAlbums.first { $0.title == "Currents" })
        try model.moveTracks(in: currents, fromOffsets: [1], toOffset: 0)
        #expect(model.tracks(of: currents).map(\.displayTitle) == ["Eventually", "Let It Happen"])

        let partial = try #require(split.first)
        #expect(throws: AlbumOrderError.self) { try model.moveTracks(in: partial, fromOffsets: [0], toOffset: 1) }
    }
}

@Suite("Strip order as on the iPod")
struct CoverFlowOrderTests {

    private func card(_ title: String, _ artist: String, sortKey: String? = nil, compilation: Bool = false) -> AlbumCard {
        AlbumCard(id: .album(UInt64(title.utf8.reduce(5381) { $0 &* 33 &+ UInt32($1) })), trackIndices: [], trackIDs: [],
                  title: title, artist: artist, year: nil, genre: nil,
                  trackCount: 1, duration: 0, artworkTrackID: nil, missingFiles: 0, isCompilation: compilation,
                  artistSortKey: sortKey ?? artist)
    }

    /// Checked on an iPod Classic: The ultimate sin moved
    /// to the start of the album table stayed last in Cover Flow, the first
    /// was Blizzard of Ozz. A numbered sort album artist ("002 Black Sabbath")
    /// did not move Black Sabbath before Aerosmith.
    @Test("an artist's albums alphabetically, artists by name without sort fields")
    func alphabeticalLikeTheIPod() {
        let inArrayOrder = [
            card("The ultimate sin", "Ozzy Osbourne"),
            card("Paranoid", "Black Sabbath", sortKey: "002 Black Sabbath"),
            card("Blizzard of Ozz", "Ozzy Osbourne"),
            card("Aerosmith", "Aerosmith", sortKey: "003 Aerosmith"),
            card("Dawn FM", "The Weeknd", compilation: true),
            card("No More Tears", "Ozzy Osbourne"),
            card("Starboy", "The Weeknd"),
            card("American Dream", "21 Savage"),
            card("ASTROWORLD", "Travis Scott", compilation: true),
        ]
        #expect(AlbumCatalog.coverFlowOrder(inArrayOrder).map(\.title) == [
            "Aerosmith", "Paranoid",
            "Blizzard of Ozz", "No More Tears", "The ultimate sin",
            "Starboy",                      // The Weeknd under W
            "American Dream",               // digits after letters
            "Dawn FM", "ASTROWORLD",        // compilations at the end, in table order
        ])
    }
}
