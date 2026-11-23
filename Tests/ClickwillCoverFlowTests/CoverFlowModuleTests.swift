import Testing
@testable import ClickwillCoverFlow

@Suite struct CoverFlowModuleTests {
    @Test func launchNameIsCoverflow() {
        #expect(CoverFlowPage(rawValue: "coverflow") == .coverFlow)
    }

    @Test func countsUseSingularForOne() {
        #expect(CoverFlowPage.count(1, "album") == "1 album")
        #expect(CoverFlowPage.count(18, "album") == "18 albums")
    }

    @MainActor @Test func keysWithoutAlbumsAreIgnored() {
        let state = CoverFlowState()
        #expect(state.handle(.rightArrow, albums: [], open: { _ in }) == .ignored)
        #expect(state.handle(.return, albums: [], open: { _ in }) == .ignored)
        #expect(state.centered == 0)
    }
}
