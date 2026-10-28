import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// The "how long to keep backups" preference and the measurement of the space backups take.
@Suite("Backup settings")
@MainActor
struct BackupSettingsTests {

    @Test("days to policy: always the three newest, 'Forever' deletes nothing")
    func retention() {
        #expect(BackupSettings.retention(days: 30) == SnapshotRetention(days: 30, alwaysKeepNewest: 3))
        #expect(BackupSettings.retention(days: BackupSettings.forever) == .keepEverything)
        #expect(BackupSettings.dayChoices.contains(BackupSettings.defaultDays))
        #expect(BackupSettings.dayChoices.last == BackupSettings.forever)
    }

    @Test("the policy from the preferences: 7 days by default, then the saved value")
    func stored() throws {
        let suite = "clickwill-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(BackupSettings.current(in: defaults) == SnapshotRetention(days: 7, alwaysKeepNewest: 3))
        defaults.set(90, forKey: BackupSettings.daysKey)
        #expect(BackupSettings.current(in: defaults) == SnapshotRetention(days: 90, alwaysKeepNewest: 3))
        defaults.set(BackupSettings.forever, forKey: BackupSettings.daysKey)
        #expect(BackupSettings.current(in: defaults) == .keepEverything)
    }

    @Test("used space: backups with the same database counted once")
    func usage() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let store = try rig.backups
        let device = try #require(rig.model.device)
        #expect(BackupUsage.measure(device: nil, store: store, retention: .standard) == nil)

        _ = try BackupService(device: device, store: store).backUpNow()
        let one = try #require(BackupUsage.measure(device: device, store: store, retention: .standard))
        #expect(one.count == 1 && one.expired == 0)
        #expect(one.bytes > 0)

        // A second backup of the same database: files hard-linked to the first.
        _ = try BackupService(device: device, store: store).backUpNow()
        let two = try #require(BackupUsage.measure(device: device, store: store, retention: .standard))
        #expect(two.count == 2)
        let naive = Self.sumOfFileSizes(in: store.root)
        #expect(two.bytes < 2 * one.bytes, "links do not double the size")
        #expect(two.bytes < naive, "each file counted once, not for every link")
    }

    /// The size counted naively - every link separately.
    static func sumOfFileSizes(in directory: URL) -> Int64 {
        let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileAllocatedSizeKey])
        var total: Int64 = 0
        while let url = walk?.nextObject() as? URL {
            total += Int64((try? url.resourceValues(forKeys: [.fileAllocatedSizeKey]))?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
