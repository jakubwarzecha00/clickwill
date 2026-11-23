import Testing
@testable import ClickwillArtists

struct ArtistsModuleTests {
    @Test func launchNameOpensTheList() {
        #expect(ArtistsPage(launchName: "artists") == .list)
        #expect(ArtistsPage(launchName: "songs") == nil)
    }

    @Test func artistPageLeadsBackToTheList() {
        #expect(ArtistsPage.artist("Ivo Brandt Trio").parent == .list)
        #expect(ArtistsPage.list.parent == nil)
        #expect(ArtistsPage.artist("Ivo Brandt Trio").title == "Ivo Brandt Trio")
    }
}
