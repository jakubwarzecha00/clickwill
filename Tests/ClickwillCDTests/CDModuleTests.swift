import Foundation
import Testing
@testable import ClickwillCD

struct CDModuleTests {
    @Test func timeLabels() {
        #expect(AudioCDScreen.time(125_000) == "2:05")
        #expect(AudioCDScreen.time(3_725_000) == "1:02:05")
    }

    @Test func pageKeepsItsVolume() {
        let volume = URL(fileURLWithPath: "/Volumes/Audio CD", isDirectory: true)
        #expect(CDPage.disc(volume).volume == volume)
    }
}
