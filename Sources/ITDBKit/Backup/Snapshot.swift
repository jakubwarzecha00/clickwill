import Foundation

/// A backup of the database and artwork from one moment.
public struct Snapshot: Codable, Sendable, Identifiable, Hashable {

    public struct Entry: Codable, Sendable, Hashable {
        /// Path relative to `iPod_Control`, e.g. `iTunes/iTunesDB`.
        public let path: String
        public let size: Int64
        public let sha256: String
        /// `true` if the file is a hard link to an identical file
        /// from an older backup - then it takes no extra space.
        public let linked: Bool
    }

    public struct Skipped: Codable, Sendable, Hashable {
        public let path: String
        public let size: Int64
        public let reason: String
    }

    /// Timestamp in the folder name, e.g. `2026-08-21T22-45-13Z`.
    public let id: String
    public let createdAt: Date
    public let deviceGUID: String
    public let volumeName: String
    /// A note for humans - the label in the app comes from `reason`.
    public let note: String?
    /// Why it was made; `nil` in backups from before reasons existed (`effectiveReason`).
    public let reason: SnapshotReason?
    public let files: [Entry]
    public let skipped: [Skipped]

    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }
    /// How much was actually added on disk - links cost nothing.
    public var addedBytes: Int64 { files.filter { !$0.linked }.reduce(0) { $0 + $1.size } }
    public var linkedCount: Int { files.count { $0.linked } }

    /// Identifiers must sort lexicographically in time order,
    /// hence ISO 8601 in UTC, with colons replaced by hyphens.
    ///
    /// The formatter is created on the spot - `ISO8601DateFormatter` is not `Sendable`,
    /// and backups are created rarely enough that sharing an instance would gain nothing.
    static func makeIdentifier(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
