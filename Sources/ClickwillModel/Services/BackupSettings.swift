import Foundation
import ITDBKit

/// How long to keep backups: the preference in days and its translation
/// into the core's policy. One place, so the settings and the write do not disagree
/// on the number of days.
public enum BackupSettings {
    public static let daysKey = "backupRetentionDays"
    public static let defaultDays = 7
    /// A sentinel value: never delete.
    public static let forever = 0
    /// The choices in the settings, shortest first.
    public static let dayChoices = [7, 14, 30, 90, 365, forever]

    /// Backups older than `days` get deleted, but the three newest always
    /// stay - after a longer break there is something to go back to.
    public static func retention(days: Int) -> SnapshotRetention {
        days == forever ? .keepEverything : SnapshotRetention(days: days, alwaysKeepNewest: 3)
    }

    /// The policy stored in the preferences - for setting up the model at launch.
    public static func current(in defaults: UserDefaults = .standard) -> SnapshotRetention {
        retention(days: defaults.object(forKey: daysKey) as? Int ?? defaultDays)
    }
}

/// How many backups of one iPod lie on the Mac and how much space they take.
///
/// A backup contains no music - only the database and artwork - so the folder does not grow
/// the way one might think. It does grow, though: every write that touches artwork adds
/// a fresh `.ithmb` file that cannot be hard-linked to an older backup.
public struct BackupUsage: Equatable, Sendable {
    public let count: Int
    /// Space actually taken on disk.
    public let bytes: Int64
    /// How many backups are outside the policy and will be deleted.
    public let expired: Int

    /// `nil` when there is no iPod or the backup folder cannot be read.
    public static func measure(device: IPodDevice?, store: SnapshotStore?, retention: SnapshotRetention) -> BackupUsage? {
        guard let device, let store,
              let snapshots = try? store.list(deviceGUID: device.identity) else { return nil }
        return BackupUsage(count: snapshots.count,
                           bytes: allocatedSize(of: store.root),
                           expired: retention.expired(among: snapshots).count)
    }

    /// The size from disk allocation, not from the sum of file sizes: identical
    /// files are hard-linked, and counted several times they would give a number several
    /// times too large. Each inode is counted once.
    static func allocatedSize(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileAllocatedSizeKey, .fileResourceIdentifierKey]
        guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys,
                                                        options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        var seen = Set<NSObject>()
        for case let url as URL in walk {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let size = values.fileAllocatedSize else { continue }
            if let identifier = values.fileResourceIdentifier as? NSObject {
                guard seen.insert(identifier).inserted else { continue }
            }
            total += Int64(size)
        }
        return total
    }
}
