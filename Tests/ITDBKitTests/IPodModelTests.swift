import Testing
import Foundation
@testable import ITDBKit

/// Model recognition. The name is cosmetic - these tests make sure it
/// **stays** that way: that an unrecognized number is shown, not guessed,
/// and that a missing number does not pretend to be certain.
@Suite("Device model")
struct IPodModelTests {

    @Test("the number from the case recovered from the device's record")
    func cleansPrefix() {
        #expect(IPodModel.clean("xA1199") == "A1199")
        #expect(IPodModel.clean(" a1238 ") == "A1238")
        #expect(IPodModel.clean("A1199") == "A1199")
        #expect(IPodModel.clean("") == nil)
    }

    @Test("an unrecognized number is shown, not guessed")
    func unknownNumberIsShownVerbatim() {
        // The model table is incomplete by design. A number that is not in it
        // must reach the screen as it is - guessing the generation from the
        // number would be inventing a fact about the device.
        #expect(IPodModel.name(for: "A9999") == "iPod A9999")
        #expect(IPodModel.name(for: "A1199") == "iPod nano (2nd generation)")
    }

    @Test("without a number we say only what follows from the database")
    func fallbackSaysOnlyWhatIsKnown() {
        func format(_ signing: DatabaseFormat.Signing) -> DatabaseFormat {
            DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: signing)
        }
        #expect(IPodModel.fallbackName(for: format(.hash58)).contains("2007 or later"))
        #expect(IPodModel.fallbackName(for: format(.presumedUnsigned)).contains("pre-2007"))
        #expect(IPodModel.fallbackName(for: format(.unknown(5))).contains("unrecognised"))
    }

    @Test("a model without a number does not pass for confirmed")
    func unconfirmedWithoutNumber() {
        let guessed = IPodModel(modelNumber: nil, name: "iPod (pre-2007)", source: .databaseOnly)
        let known = IPodModel(modelNumber: "A1199", name: "iPod nano (2nd generation)", source: .sysInfo)
        #expect(guessed.isConfirmed == false)
        #expect(known.isConfirmed)
    }

    @Test("reads the number from the old SysInfo")
    func readsSysInfo() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SysInfo-\(UUID().uuidString)")
        try """
            boardHwSwInterfaceRev: 0x00080000
            ModelNumStr: xA1199
            FirewireGuid: 0x000A27001234ABCD
            """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(IPodModel.fromSysInfo(at: url) == "A1199")
    }

    @Test("a missing file means a missing number, not an error")
    func missingFileIsNotAnError() {
        let absent = URL(fileURLWithPath: "/no/such/SysInfo")
        #expect(IPodModel.fromSysInfo(at: absent) == nil)
        #expect(IPodModel.fromSysInfoExtended(at: absent) == nil)
    }
}
