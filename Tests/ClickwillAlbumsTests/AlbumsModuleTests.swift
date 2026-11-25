import Testing
import SwiftUI
@testable import ClickwillAlbums

@Suite struct AlbumsModuleTests {
    @Test func launchNames() {
        #expect(AlbumsPage(rawValue: "albums") == .albums)
        #expect(AlbumsPage(rawValue: "reorder") == .reorder)
    }

    @Test func reorderSelectsTheAlbumsRow() {
        #expect(AlbumsPage.reorder.sidebarPage == .albums)
    }

    @MainActor @Test func keysWithoutAlbumsAreIgnored() {
        let state = AlbumsState()
        #expect(state.handle(.downArrow, characters: "", albums: [], letter: { _ in "" }, open: { _ in }) == .ignored)
        #expect(state.handle(KeyEquivalent("a"), characters: "a", albums: [], letter: { _ in "A" }, open: { _ in }) == .ignored)
        #expect(state.centered == 0)
    }

    private func defaults() -> UserDefaults {
        let name = "AlbumsModuleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @MainActor @Test func layoutIsRemembered() {
        let defaults = defaults()
        #expect(AlbumsState(defaults: defaults).layout == .wheel)
        AlbumsState(defaults: defaults).layout = .grid
        #expect(AlbumsState(defaults: defaults).layout == .grid)
    }

    /// Ten albums in rows of four: 0-3, 4-7, 8-9.
    @Test func gridRowsMoveByAWholeRow() {
        #expect(AlbumsState.rowNeighbor(of: 5, up: true, columns: 4, count: 10) == 1)
        #expect(AlbumsState.rowNeighbor(of: 1, up: false, columns: 4, count: 10) == 5)
        #expect(AlbumsState.rowNeighbor(of: 2, up: true, columns: 4, count: 10) == 2)
        #expect(AlbumsState.rowNeighbor(of: 8, up: false, columns: 4, count: 10) == 8)
    }

    @Test func downOverAShorterLastRowGoesToTheLastAlbum() {
        #expect(AlbumsState.rowNeighbor(of: 7, up: false, columns: 4, count: 10) == 9)
        #expect(AlbumsState.rowNeighbor(of: 5, up: false, columns: 4, count: 10) == 9)
    }

    @Test func searchMatchesEveryWordInTitleOrArtist() {
        let words = AlbumsState.words(of: "  night  juniper ")
        #expect(words == ["night", "juniper"])
        #expect(AlbumsState.matches(title: "Night Shift Utopia", artist: "Juniper Static", words: words))
        #expect(!AlbumsState.matches(title: "Night Market", artist: "Neon Pilgrims", words: words))
    }

    @Test func searchIgnoresCaseAndAccents() {
        #expect(AlbumsState.matches(title: "Café Société", artist: "", words: ["cafe", "SOCIETE"]))
        #expect(AlbumsState.words(of: "   ").isEmpty)
    }

    @Test func gridFitsColumnsToTheWidth() {
        let narrow = GridGeometry(width: 300)
        #expect(narrow.columns == 1)
        let wide = GridGeometry(width: 1200)
        #expect(wide.columns == 6)
        #expect(wide.cell >= GridGeometry.minCell)
        #expect(CGFloat(wide.columns) * wide.cell + CGFloat(wide.columns - 1) * wide.spacing <= 1200 - 2 * GridGeometry.margin)
    }
}
