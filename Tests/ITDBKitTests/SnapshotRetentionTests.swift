import Testing
import Foundation
@testable import ITDBKit

/// Deleting backups is the only operation in this app that nothing
/// undoes. The decision of what to delete is a pure function precisely so that it can
/// be checked without touching the disk.
@Suite("Backup retention")
struct SnapshotRetentionTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(daysAgo: Double) -> Snapshot {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        return Snapshot(id: Snapshot.makeIdentifier(from: date), createdAt: date,
                        deviceGUID: "TEST", volumeName: "iPod", note: nil, reason: nil, files: [], skipped: [])
    }

    @Test("older than the limit get deleted, younger ones stay")
    func cutoff() {
        let all = (0..<12).map { snapshot(daysAgo: Double($0)) }
        let expired = SnapshotRetention(days: 7, alwaysKeepNewest: 0).expired(among: all, now: now)
        #expect(expired.count == 4, "days 8, 9, 10 and 11 are older than a week")
        #expect(expired.allSatisfy { $0.createdAt < now.addingTimeInterval(-7 * 86_400) })
    }

    @Test("the three newest stay regardless of age")
    func floorWins() {
        // A month's break: everything is older than the limit. Without the floor
        // the first write after coming back would delete the whole history.
        let all = (30..<40).map { snapshot(daysAgo: Double($0)) }
        let expired = SnapshotRetention.standard.expired(among: all, now: now)
        #expect(all.count - expired.count == 3)
        let kept = Set(all.map(\.id)).subtracting(expired.map(\.id))
        #expect(kept == Set(all.sorted { $0.createdAt > $1.createdAt }.prefix(3).map(\.id)),
                "the three newest must stay, not any three")
    }

    @Test("the input order does not matter")
    func orderIndependent() {
        let all = (0..<12).map { snapshot(daysAgo: Double($0)) }
        let forward = SnapshotRetention.standard.expired(among: all, now: now).map(\.id).sorted()
        let backward = SnapshotRetention.standard.expired(among: all.reversed(), now: now).map(\.id).sorted()
        #expect(forward == backward)
    }

    @Test("\"never delete\" deletes nothing")
    func keepEverything() {
        let all = (0..<400).map { snapshot(daysAgo: Double($0)) }
        #expect(SnapshotRetention.keepEverything.expired(among: all, now: now).isEmpty)
    }

    @Test("an empty folder does not blow up")
    func empty() {
        #expect(SnapshotRetention.standard.expired(among: [], now: now).isEmpty)
    }
}
