import Foundation
import ITDBKit

/// What restoring a backup will do to the iPod - computed before the user clicks.
public struct BackupPreview: Sendable {
    public let snapshot: Snapshot
    public let songCount: Int
    public let albumCount: Int
    /// Tracks that are on the iPod now, but not in the backup. After the restore
    /// they disappear from the menu, but their files stay - a backup does not contain music files.
    public let songsAddedSince: Int
    /// Tracks from the backup that are not on the iPod today.
    public let songsRemovedSince: Int
    /// Tracks from the backup whose file disappeared from the iPod (deleted or replaced
    /// after the backup was made). They come back to the menu as entries without a file.
    public let songsWithoutFile: Int

    /// What the write made right after this backup changed - the answer to the question
    /// "what was that «1 change» about".
    public let writeAfter: LibraryDiff
    /// How far `writeAfter` reaches: the next backup with a different database, or `nil`
    /// when it was the last write and we compare with the current state.
    public let writeAfterUntil: Snapshot?
    /// What the restore will change: from the current state to the state in the backup.
    public let restoring: LibraryDiff
    /// Tracks that will come back without a file - by name, not just by count.
    public let withoutFile: [LibraryDiff.Song]
}

public enum BackupRestoreError: Error, CustomStringConvertible {
    case notConnected
    case pendingChanges(Int)

    public var description: String {
        switch self {
        case .notConnected: "restore needs the iPod the backup came from"
        case .pendingChanges(let count): "restore blocked by \(count) pending changes"
        }
    }
}

/// Backups of one connected iPod: the list, an on-demand backup, a preview
/// and a restore. It does not know the model - it gets the device and the backup store,
/// and returns values. Whether restoring is allowed at a given moment (demo
/// mode, unsaved changes) is checked by the caller. `ipodctl restore` also
/// restores through it - one path for the app and the tool.
public struct BackupService {
    let device: IPodDevice
    let store: SnapshotStore
    var files: any FileSystem = LocalFileSystem()
    /// Whether Music is open - a restore is a database write, so the same
    /// block applies as for Write to iPod. The app passes the state from its
    /// environment (`LibraryEnvironment`), as for a regular write; without this
    /// the restore test failed when Music was open on the Mac.
    var isMusicRunning: @Sendable () -> Bool = IPodDevice.isMusicRunning

    public init(device: IPodDevice, store: SnapshotStore, files: any FileSystem = LocalFileSystem(),
                isMusicRunning: @escaping @Sendable () -> Bool = IPodDevice.isMusicRunning) {
        self.device = device
        self.store = store
        self.files = files
        self.isMusicRunning = isMusicRunning
    }

    /// Backups of this iPod, newest first.
    func list() -> [Snapshot] { (try? store.list(deviceGUIDs: device.identities)) ?? [] }

    /// An on-demand backup - before something another program will do to the iPod
    /// (for example Music). Only reads the device; does not write to the iPod.
    func backUpNow() throws -> Snapshot {
        try store.capture(from: device, reason: .manual, note: "Clickwill: manual backup")
    }

    /// Computes what a restore will change - without touching the device. `fallback`:
    /// the library in memory, when the database on the iPod cannot be read.
    func preview(_ snapshot: Snapshot, fallback: ITLibrary) throws -> BackupPreview {
        let backup = try store.readLibrary(of: snapshot)
        let paths = device.paths

        // The current state from disk, not from memory: unsaved changes in the app
        // are not part of what the restore will undo.
        let onDisk = (try? device.readLibrary()) ?? fallback
        let nowIDs = Set(onDisk.tracks.map(\.persistentID))
        let backupIDs = Set(backup.tracks.map(\.persistentID))
        let withoutFile = backup.tracks.filter { track in
            guard let url = track.fileURL(on: paths) else { return false }
            return !files.fileExists(at: url)
        }.map(LibraryDiff.song)

        // The next newer backup with a **different** database. One write sometimes makes two
        // backups right after each other (before touching files and before the database itself) - they have
        // an identical database, and comparing with the twin would say "nothing happened".
        let all = list()
        let ownDigest = Self.databaseDigest(of: snapshot)
        var until: Snapshot?
        if let index = all.firstIndex(where: { $0.id == snapshot.id }) {
            until = all[..<index].reversed().first { Self.databaseDigest(of: $0) != ownDigest }
        }
        let after = try until.map { try store.readLibrary(of: $0) } ?? onDisk

        return BackupPreview(
            snapshot: snapshot,
            songCount: backup.tracks.count,
            albumCount: Set(backup.tracks.map { $0.album ?? "" }).count,
            songsAddedSince: nowIDs.subtracting(backupIDs).count,
            songsRemovedSince: backupIDs.subtracting(nowIDs).count,
            songsWithoutFile: withoutFile.count,
            writeAfter: LibraryDiff(from: backup, to: after),
            writeAfterUntil: until,
            restoring: LibraryDiff(from: onDisk, to: backup),
            withoutFile: withoutFile)
    }

    /// Checksum of the database alone in the backup - for recognizing twin backups.
    static func databaseDigest(of snapshot: Snapshot) -> String? {
        snapshot.files.first { $0.path == "iTunes/iTunesDB" }?.sha256
    }

    /// Restores a backup to the iPod. Returns a backup of the state **from before** the restore -
    /// i.e. the way to undo it.
    ///
    /// This is not a bare copy of the backup's files onto the device, even though that is what
    /// `SnapshotStore.restore` looks like. The database goes through the regular write path, which gives:
    ///
    /// - the "Music closed" gate and the check that the database has not changed since
    ///   loading (`expectedSourceDigest`),
    /// - **a backup of the current state before the restore** - a mistake can be undone,
    /// - signing, reparsing, flushing to the medium and an atomic swap,
    /// - merging `Play Counts`. That file refers to tracks by their order
    ///   in the database; left next to the old database it would assign plays to other
    ///   songs on the next write.
    ///
    /// Play history **does not go back**. A backup restores the library and the edits,
    /// while the play count and the last-played date carry over from the current state - otherwise
    /// restoring a week-old backup would erase a week of listening.
    ///
    /// Music files are not touched: the backup does not contain them. Tracks added after
    /// the backup disappear from the menu, but their files stay - that is why restoring
    /// a newer backup brings them back.
    public func restore(_ snapshot: Snapshot, expectedSourceDigest: String?) throws -> Snapshot {
        guard device.supportsWriting else {
            throw ITDBError.writeRefused(.readOnly(device.readOnlyReason))
        }
        let lock = try store.writeLock(for: device)
        defer { withExtendedLifetime(lock) {} }
        // Checksums, before anything touches the iPod.
        try store.verify(snapshot)

        let restored = try store.readLibrary(of: snapshot)
            .carryingPlayHistory(from: try device.readLibrary())

        var options = WriteOptions()
        options.expectedSourceDigest = expectedSourceDigest
        options.isMusicRunning = isMusicRunning
        let written = try device.writeDatabase(
            restored, using: store, reason: .beforeRestore,
            note: "Clickwill: before restoring backup \(snapshot.id)", options: options)

        // Artwork after the database: the pre-restore backup the writer made still has
        // the current artwork at that point, so it is consistent. If this part
        // fails, we go back entirely to that state.
        do {
            try store.restore(snapshot, to: device, include: SnapshotStore.artworkOnly)
        } catch {
            try? store.restore(written.snapshot, to: device)
            throw error
        }
        return written.snapshot
    }
}
