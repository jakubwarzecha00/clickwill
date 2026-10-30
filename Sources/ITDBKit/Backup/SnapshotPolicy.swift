import Foundation

/// What goes into a backup and what does not.
///
/// Excluding a file is safe, because restoring only overwrites what is in
/// the manifest - it never deletes anything. A skipped file stays untouched on the iPod.
public struct SnapshotPolicy: Sendable {
    public struct Exclusion: Sendable, Hashable {
        public let fileName: String
        public let reason: String
    }

    public let exclusions: [Exclusion]

    /// Files whose absence from the manifest must be an error, not a silent loss.
    public let requiredPaths: [String]

    public init(exclusions: [Exclusion], requiredPaths: [String]) {
        self.exclusions = exclusions
        self.requiredPaths = requiredPaths
    }

    public static let standard = SnapshotPolicy(
        exclusions: [
            Exclusion(
                fileName: "iTunesControl",
                reason: """
                    iTunes presence marker - nothing in the database refers to it. \
                    On one device it was 156 MB and contained raw macOS heap pointers, \
                    so it is a crash artifact of some app, not iPod data.
                    """
            )
        ],
        requiredPaths: ["iTunes/iTunesDB"]
    )

    public func exclusion(forFileNamed name: String) -> Exclusion? {
        exclusions.first { $0.fileName == name }
    }
}


/// How long we keep backups.
///
/// A database backup costs 2.4 MB, but every write that touches artwork adds a fresh
/// copy of `F1060_1.ithmb` - 28 MB that cannot be hard-linked because the file
/// changed. Those drive the growth of the folder, not the database itself.
public struct SnapshotRetention: Sendable, Hashable {
    /// Backups younger than this many days are always kept.
    public let days: Int
    /// How many of the newest backups are kept **regardless of age**.
    ///
    /// Without this, leaving the iPod unplugged for a week would be enough for
    /// not a single backup to survive the next write - and then the first thing
    /// the app does after a long break is delete everything that could be used
    /// to roll back. The floor is there so that the rule "a backup
    /// before every write" means something in that case too.
    public let alwaysKeepNewest: Int
    /// Backups kept regardless of age (`Snapshot.id`) - the one from before the first write
    /// on an experimental iPod.
    public var pinned: Set<String> = []

    public init(days: Int, alwaysKeepNewest: Int) {
        self.days = days
        self.alwaysKeepNewest = alwaysKeepNewest
    }

    /// Seven days, at least three backups.
    public static let standard = SnapshotRetention(days: 7, alwaysKeepNewest: 3)
    /// Delete nothing - for the CLI and tests that need the full history.
    public static let keepEverything = SnapshotRetention(days: .max, alwaysKeepNewest: .max)

    /// Which backups get deleted. `snapshots` arrives newest first.
    /// A pure function - the decision can be checked without touching the disk.
    public func expired(among snapshots: [Snapshot], now: Date = Date()) -> [Snapshot] {
        guard days != .max, alwaysKeepNewest != .max else { return [] }
        let newestFirst = snapshots.sorted { $0.createdAt > $1.createdAt }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return newestFirst.enumerated().compactMap { position, snapshot in
            if position < alwaysKeepNewest || pinned.contains(snapshot.id) { return nil }
            return snapshot.createdAt < cutoff ? snapshot : nil
        }
    }
}
