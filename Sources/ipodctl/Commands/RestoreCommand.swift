import Foundation
import ITDBKit
import ClickwillModel

/// `restore ID` - restoring a backup to the device the same way as in the app
/// (`BackupService.restore`): under the lock, checksums before the write, a backup
/// of the current state, the play history stays, and artwork comes back together with the database.
enum RestoreCommand {
    static func run(_ call: Invocation) async throws {
        guard let id = call.positional().first else { throw CommandError("give a backup identifier") }
        let device = try openDevice(call)
        let store = try openStore(call)
        let snapshot = try store.snapshot(deviceGUID: device.identity, id: id)
        let before = try BackupService(device: device, store: store).restore(snapshot, expectedSourceDigest: nil)
        print("Restored backup \(snapshot.id) - \(snapshot.files.count) files.")
        print("  State from before the restore: backup \(before.id)")
    }
}
