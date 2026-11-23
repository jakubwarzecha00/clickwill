import Testing
import ClickwillModel
@testable import ClickwillChanges

@Suite struct ChangesModuleTests {
    @Test func pendingTitleAgreesWithTheCount() {
        #expect(ChangesStatusItems.pendingTitle(1) == "1 change pending")
        #expect(ChangesStatusItems.pendingTitle(3) == "3 changes pending")
    }

    @Test func emptyFieldsReadAsSetAndClear() {
        let set = PendingChange(.trackEdited(album: "Field Notes", track: "Ridge", field: "year", from: "", to: "2019"))
        let clear = PendingChange(.albumEdited(album: "Field Notes", field: "genre", from: "Folk", to: "", tracks: 1))
        #expect(set.summary == "In “Field Notes”: set the year of “Ridge” to 2019")
        #expect(clear.summary == "“Field Notes”: clear genre “Folk” (1 song)")
    }

    @Test func renamingATrackNamesItOnce() {
        let change = PendingChange(.trackEdited(album: "Field Notes", track: "Ridge", field: "title", from: "Ridge", to: "The Ridge"))
        #expect(change.summary == "In “Field Notes”: rename “Ridge” to “The Ridge”")
    }

    @Test func addingSongsCountsConversions() {
        let change = PendingChange(.tracksAdded(tracks: 6, albums: 1, bytes: 0, converting: 6))
        #expect(change.summary.hasPrefix("Add 6 songs (1 album, "))
        #expect(change.summary.hasSuffix(", 6 to be converted first)"))
    }
}
