import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillDevice

@Suite("Device module")
struct DeviceModuleTests {
    /// `--screen overview` and `--screen backups` reach the pages by their raw value.
    @Test func pagesAreNamedForTheCommandLine() {
        #expect(DevicePage(rawValue: "overview") == .overview)
        #expect(DevicePage(rawValue: "backups") == .backups)
        #expect(DevicePage.allCases.map(\.title) == ["Overview", "Backups"])
    }

    private func backup(_ reason: SnapshotReason?, note: String? = nil) -> Snapshot {
        Snapshot(id: "test", createdAt: Date(timeIntervalSince1970: 1_800_000_000), deviceGUID: "TEST",
                 volumeName: "iPod", note: note, reason: reason, files: [], skipped: [])
    }

    @Test func backupReasons() {
        #expect(BackupLabels.reason(backup(.manual)) == "Made by hand")
        #expect(BackupLabels.reason(backup(.beforeWrite(changes: 1))) == "Before writing 1 change")
        #expect(BackupLabels.reason(backup(.beforeWrite(changes: 3))) == "Before writing 3 changes")
        #expect(BackupLabels.reason(backup(.beforeWrite(changes: nil))) == "Before a write")
        #expect(BackupLabels.reason(backup(nil)) == "Automatic backup")
    }
}
