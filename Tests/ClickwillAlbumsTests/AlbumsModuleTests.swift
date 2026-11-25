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
}
