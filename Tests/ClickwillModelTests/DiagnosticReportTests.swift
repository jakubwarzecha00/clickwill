import Testing
@testable import ClickwillModel

@Suite("Diagnostic report")
struct DiagnosticReportTests {

    @Test("the GUID, paths and the iPod name do not leave in the report")
    func redactsInstanceIdentifiers() {
        let text = "Device/SysInfoExtended gives GUID 000A27001234ABCD (0x000a27001234abcd) "
                 + "in /Volumes/Anna's iPod/iPod_Control, backup in /Users/anna/Library - Anna's iPod"
        let clean = DiagnosticReport.redacted(text, names: ["Anna's iPod"])
        #expect(!clean.contains("1234ABCD") && !clean.lowercased().contains("1234abcd"))
        #expect(!clean.contains("Anna") && !clean.contains("anna"))
        #expect(clean.contains("<GUID>") && clean.contains("/Volumes/<iPod>/iPod_Control") && clean.contains("<path in your home folder>"))
    }

    @Test("paths in the home folder and file names do not leave in the report")
    func redactsFileNames() {
        let text = "could not read /Users/anna/Documents/Private-client-A.ithmb\n"
                 + "missing /Volumes/iPod/iPod_Control/Music/F05/Secret Song.m4a and cover.jpg"
        let clean = DiagnosticReport.redacted(text)
        #expect(!clean.contains("Private-client-A") && !clean.contains("Documents"))
        #expect(!clean.contains("Song.m4a") && !clean.contains("cover.jpg"))
        #expect(clean.contains("could not read <path in your home folder>"))
        #expect(clean.contains("/Volumes/<iPod>/iPod_Control/Music/F05/"))
    }

    @Test("the default name iPod does not break model names")
    func keepsGenericName() {
        #expect(DiagnosticReport.redacted("iPod classic", names: ["iPod"]) == "iPod classic")
    }
}
