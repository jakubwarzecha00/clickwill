import Testing
import ClickwillShared
@testable import ClickwillThemes

@MainActor
struct ThemeStoreTests {
    @Test func startsWithTheStandardTheme() {
        #expect(ThemeStore().current == .standard)
    }
}
