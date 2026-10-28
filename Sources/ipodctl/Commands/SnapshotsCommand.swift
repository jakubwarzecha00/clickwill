import Foundation
import ITDBKit

/// `snapshots` - the list of the iPod's backups.
enum SnapshotsCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let snapshots = try openStore(call).list(deviceGUID: device.identity)
        guard !snapshots.isEmpty else {
            print("No backups for \(device.identity).")
            return
        }
        for snapshot in snapshots {
            let note = snapshot.note.map { "  \($0)" } ?? ""
            print("\(snapshot.id)  \(snapshot.files.count) files  \(formatted(bytes: snapshot.totalBytes))\(note)")
        }
    }
}
