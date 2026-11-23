import Testing
@testable import ClickwillImport

@Suite struct ImportModuleTests {
    @Test func confirmTitleNamesReplacementsAndSkips() {
        #expect(ImportSheet.confirmTitle(add: 3, replace: 0, skipped: 0) == "Add to Library")
        #expect(ImportSheet.confirmTitle(add: 3, replace: 0, skipped: 1) == "Add 3 to Library")
        #expect(ImportSheet.confirmTitle(add: 0, replace: 1, skipped: 0) == "Replace 1 File")
        #expect(ImportSheet.confirmTitle(add: 0, replace: 4, skipped: 2) == "Replace 4 Files")
        #expect(ImportSheet.confirmTitle(add: 2, replace: 1, skipped: 0) == "Add 2, Replace 1")
    }

    @Test func alertTitlesAgreeWithTheCount() {
        #expect(ImportSheet.skippableTitle(count: 1) == "Add 1 Song Your iPod May Skip?")
        #expect(ImportSheet.skippableTitle(count: 3) == "Add 3 Songs Your iPod May Skip?")
        #expect(ImportSheet.refusalTitle(count: 1) == "1 Song Wasn't Added")
        #expect(ImportSheet.refusalTitle(count: 2) == "2 Songs Weren't Added")
    }
}
