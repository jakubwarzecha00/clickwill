import Testing
@testable import ClickwillSongs

struct SongsModuleTests {
    @Test func pageNamesMatchTheLaunchFlag() {
        #expect(SongsPage(rawValue: "songs") == .songs)
        #expect(SongsPage.songs.title == "Songs")
    }
}
