import Testing
@testable import ClickwillCoverFlow

@Suite struct CoverFlowModuleTests {
    @Test func launchNameIsCoverflow() {
        #expect(CoverFlowPage(rawValue: "coverflow") == .coverFlow)
    }

    @MainActor @Test func keysWithoutAlbumsAreIgnored() {
        let state = CoverFlowState()
        #expect(state.handle(.rightArrow, albums: [], open: { _ in }) == .ignored)
        #expect(state.handle(.return, albums: [], open: { _ in }) == .ignored)
        #expect(state.centered == 0)
    }
}
