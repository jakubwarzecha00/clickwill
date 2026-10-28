import Foundation
import ITDBKit

/// Backups for the views - the work is in `BackupService`, here only what
/// depends on the app state: demo mode, unsaved changes,
/// reloading the library after a restore.
extension LibraryModel {

    /// Backups of the connected iPod, newest first.
    public func backups() -> [Snapshot] {
        guard let device, let store = try? environment.backups() else { return [] }
        return BackupService(device: device, store: store, files: environment.files).list()
    }

    /// An on-demand backup. Only reads the device; does not write to the iPod.
    @discardableResult
    public func backUpNow() throws -> Snapshot {
        if writesBlocked { throw WriteBlocked.demoCopy }
        guard let device else { throw BackupRestoreError.notConnected }
        return try BackupService(device: device, store: try environment.backups(), files: environment.files).backUpNow()
    }

    /// Computes what a restore will change - without touching the device.
    public func preview(_ snapshot: Snapshot) async throws -> BackupPreview {
        guard let device, let current = library else { throw BackupRestoreError.notConnected }
        return try BackupService(device: device, store: try environment.backups(), files: environment.files).preview(snapshot, fallback: current)
    }

    /// Restores a backup to the connected iPod (`BackupService.restore`) and reloads
    /// the library. Returns a backup of the state from before the restore.
    @discardableResult
    public func restoreBackup(_ snapshot: Snapshot) async throws -> Snapshot {
        if writesBlocked { throw WriteBlocked.demoCopy }
        guard state == .loaded, let device, isWritable, let source else { throw BackupRestoreError.notConnected }
        guard changes.isEmpty else { throw BackupRestoreError.pendingChanges(changes.log.count) }
        let undo = try BackupService(device: device, store: try environment.backups(), files: environment.files,
                                     isMusicRunning: environment.isMusicRunning)
            .restore(snapshot, expectedSourceDigest: sourceDigest)
        await load(source)
        return undo
    }
}
