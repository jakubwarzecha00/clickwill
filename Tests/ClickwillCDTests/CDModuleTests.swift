import Foundation
import Testing
@testable import ClickwillCD

struct CDModuleTests {
    @Test @MainActor func timeLabels() {
        #expect(AudioCDScreen.time(125_000) == "2:05")
        #expect(AudioCDScreen.time(3_725_000) == "1:02:05")
    }

    @Test func pageKeepsItsVolume() {
        let volume = URL(fileURLWithPath: "/Volumes/Audio CD", isDirectory: true)
        #expect(CDPage.disc(volume).volume == volume)
    }

    private let first = URL(fileURLWithPath: "/Volumes/First", isDirectory: true)
    private let second = URL(fileURLWithPath: "/Volumes/Second", isDirectory: true)

    @Test func insertedDiscOpensItsPage() {
        #expect(DiscChange.decide(appeared: first, removed: false, shown: nil, shownIsRipping: false,
                                  shownRemains: false, sheetIsOpen: false) == .show(first))
        #expect(DiscChange.decide(appeared: second, removed: false, shown: first, shownIsRipping: false,
                                  shownRemains: true, sheetIsOpen: false) == .show(second))
    }

    @Test func insertedDiscWaitsForASheetOrARip() {
        #expect(DiscChange.decide(appeared: first, removed: false, shown: nil, shownIsRipping: false,
                                  shownRemains: false, sheetIsOpen: true) == .nothing)
        #expect(DiscChange.decide(appeared: second, removed: false, shown: first, shownIsRipping: true,
                                  shownRemains: true, sheetIsOpen: false) == .nothing)
    }

    @Test func removedDiscOnScreenGoesHome() {
        #expect(DiscChange.decide(appeared: nil, removed: true, shown: first, shownIsRipping: false,
                                  shownRemains: false, sheetIsOpen: false) == .showHome)
        // Behind a sheet too: the page would show an ejected disc.
        #expect(DiscChange.decide(appeared: second, removed: true, shown: first, shownIsRipping: false,
                                  shownRemains: false, sheetIsOpen: true) == .showHome)
    }

    @Test func removingAnotherVolumeKeepsTheScreen() {
        #expect(DiscChange.decide(appeared: nil, removed: true, shown: first, shownIsRipping: false,
                                  shownRemains: true, sheetIsOpen: false) == .nothing)
        #expect(DiscChange.decide(appeared: nil, removed: true, shown: nil, shownIsRipping: false,
                                  shownRemains: false, sheetIsOpen: false) == .nothing)
    }
}
