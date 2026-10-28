import Foundation
import ITDBKit

/// `backup [--note TEXT]` - a backup of the database and artwork.
enum BackupCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let snapshot = try openStore(call).capture(from: device, reason: .manual, note: call.value(for: "--note"))
        report("Backup created", [
            ("identifier", snapshot.id),
            ("files", "\(snapshot.files.count), of which \(snapshot.linkedCount) linked to older backups"),
            ("size", "\(formatted(bytes: snapshot.totalBytes)), added on disk \(formatted(bytes: snapshot.addedBytes))"),
        ])
        for entry in snapshot.skipped {
            print("\n  skipped \(entry.path) (\(formatted(bytes: entry.size)))")
            print("    reason: \(entry.reason)")
        }
    }
}
