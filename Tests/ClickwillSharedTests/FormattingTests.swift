import Foundation
import Testing
import ClickwillShared

@Suite("Numbers and strings for the interface")
struct FormattingTests {
    @Test func firstLetterCase() {
        #expect("Today at 2:22".lowercasedFirst == "today at 2:22")
        #expect("this alpha".capitalizedFirst == "This alpha")
        #expect("".lowercasedFirst == "")
    }

    @Test func durations() {
        #expect(TimeInterval(125.4).clockLabel == "2:05")
        #expect(TimeInterval(3599.6).minutesLabel == "60 min")
    }

    @Test func gigabytes() {
        #expect(Int64(159_839_977_472).gigabytes == "159.8 GB")
    }
}
