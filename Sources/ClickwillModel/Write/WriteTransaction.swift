import Foundation
import CoreGraphics
import ITDBKit

/// Writing changes to the iPod - one path for the app and `ipodctl`.
///
/// Order:
///
/// 1. Gates: writing allowed, one write at a time (a lock), the database on the iPod
///    the same as when loaded, Music closed, a backup - all
///    before the first change on the iPod.
/// 2. Phases before the database (`WritePhase`), each writing itself into the write ledger
///    (`WriteLedger`): new artwork records, conversions, restored files,
///    added tracks - the database must point to them - and finally the repairs on
///    every write (`RepairPhase`).
/// 3. The database write (`IPodDevice.writeDatabase`).
/// 4. After the database write: deleting files and replacing artwork (`AfterWritePhase`),
///    the order intent, pruning old backups.
///
/// When something stops the transaction before the database write, or the write itself fails,
/// the transaction rolls back what it did on the iPod: it deletes the files it put there,
/// and restores the artwork from the backup made before the first change. The caller
/// gets an error and does not change its state.
///
/// It does not run on the interface thread: it takes values and returns values.
public struct WriteTransaction: Sendable {
    public var library: ITLibrary
    public var changes: ChangeSet
    public var device: IPodDevice
    /// Format limits - to check whether the iPod plays a transcoded file.
    public var capabilities: IPodCapabilities
    public var environment: LibraryEnvironment
    /// The database digest from the moment of loading; a different database on the iPod - a refusal.
    public var expectedSourceDigest: String?
    public var backupRetention: SnapshotRetention = .standard
    /// Writes even with Music running (`ipodctl --allow-music`).
    public var allowWhileMusicRunning = false
    /// Description of the backup before the database write - for humans.
    public var note: String
    /// The reason for the backup before the database write - the app names it by this.
    public var backupReason: SnapshotReason = .beforeWrite(changes: nil)
    /// The jump bar in the order intent saved after the write
    /// (`ipodctl order --move --jump flat`).
    public var orderIntentJumpTable: JumpTablePolicy = .derived
    /// One line per file or artwork - for `ipodctl`.
    public var progress: (@Sendable (String) -> Void)?

    public init(library: ITLibrary, changes: ChangeSet, device: IPodDevice, capabilities: IPodCapabilities,
                environment: LibraryEnvironment, note: String) {
        self.library = library
        self.changes = changes
        self.device = device
        self.capabilities = capabilities
        self.environment = environment
        self.note = note
    }

    /// The result of a successful write.
    public struct Result: Sendable {
        public let outcome: WriteOutcome
        /// The library exactly as it went to disk.
        public let writtenLibrary: ITLibrary
        /// Digest of the written database - the reference point for the next write.
        public let sourceDigest: String
        /// What did not go in and keeps waiting: requests that failed, and files
        /// that could not be deleted - with their log entries
        /// (`ChangeSet.remaining(after:)`).
        public let remaining: ChangeSet
        /// Artwork of new albums by track `persistentID`.
        public let coverImages: [UInt64: CGImage]
        /// Whether `ArtworkDB` on the iPod changed.
        public let artworkChanged: Bool
        /// Whether any track got a new file (conversion, restore, replacement).
        public let filesReplaced: Bool
    }

    public func run() async throws -> Result {
        guard device.supportsWriting else {
            throw ITDBError.writeRefused(.readOnly(device.readOnlyReason))
        }
        let store = try environment.backups()
        let lock = try store.writeLock(for: device)
        defer { withExtendedLifetime(lock) {} }
        try device.ensureDatabaseUnchanged(since: expectedSourceDigest)
        // Before the first change on the iPod - also before the repairs that write
        // `ArtworkDB`. The writer checks the same again right before the database.
        if let issue = device.preflightForWriting(isMusicRunning: environment.isMusicRunning)
            .refusal(allowingMusic: allowWhileMusicRunning) {
            throw ITDBError.writeRefused(.preflight(issue))
        }

        var ledger = WriteLedger()
        if changes.touchesFilesBeforeDatabase {
            try ledger.backUpOnce(device, in: store, reason: .beforeFiles, note: "Clickwill: before file changes")
        }
        var library = self.library
        let written: DatabaseWriteResult
        do {
            for phase in phasesBeforeDatabase(store: store) {
                try await phase.run(&library, on: device, ledger: &ledger)
            }
            written = try device.writeDatabase(library, using: store, reason: backupReason, note: note, options: writeOptions)
        } catch {
            rollBack(ledger, store: store)
            throw error
        }

        AfterWritePhase(filesToDelete: changes.filesToDelete, archiveBeforeDelete: changes.archiveBeforeDelete,
                        replacements: changes.artworkReplacements, files: environment.files)
            .run(on: device, ledger: &ledger)
        // From the library that went to disk - with added tracks where they were placed.
        let intentSaved = saveOrderIntent(of: written.writtenLibrary)
        // An error cleaning up backups has no right to undermine the write - `prune` does not throw.
        let pruned = store.prune(deviceGUIDs: device.identities, retention: backupRetention).count

        return Result(outcome: WriteOutcome(result: written, ledger: ledger, orderIntentSaved: intentSaved, prunedBackups: pruned),
                      writtenLibrary: written.writtenLibrary, sourceDigest: written.digest,
                      remaining: changes.remaining(after: ledger.completed), coverImages: ledger.coverImages,
                      artworkChanged: ledger.artworkChanged, filesReplaced: ledger.filesReplaced)
    }

    /// Phases before the database write, in this order: the database must point to finished
    /// images and files, and the repairs run on the library with all changes.
    private func phasesBeforeDatabase(store: SnapshotStore) -> [any WritePhase] {
        [
            NewCoversPhase(jobs: changes.artworkAdditions, sharing: changes.artworkSharing, progress: progress),
            ConversionPhase(jobs: changes.conversions, capabilities: capabilities, progress: progress),
            FileImportPhase(jobs: changes.fileImports, capabilities: capabilities),
            AdditionPhase(additions: changes.additions, progress: progress),
            RepairPhase(artworkOwnerRedirects: changes.artworkOwnerRedirects,
                        replacedArtwork: Set(changes.artworkReplacements.values.map(\.album)), store: store),
        ]
    }

    private var writeOptions: WriteOptions {
        var options = WriteOptions()
        options.expectedSourceDigest = expectedSourceDigest
        options.playCountRedirects = changes.playCountRedirects
        options.isMusicRunning = environment.isMusicRunning
        options.allowWhileMusicRunning = allowWhileMusicRunning
        return options
    }

    private func saveOrderIntent(of library: ITLibrary) -> Bool {
        do {
            try environment.orderIntents().save(library.captureOrderIntent(jumpTable: orderIntentJumpTable),
                                                deviceGUID: device.identity)
            return true
        } catch {
            return false
        }
    }

    /// Rolling back changes on the iPod after a failed transaction - only on the same
    /// volume. Files it put there go to the trash; `ArtworkDB` and `.ithmb`
    /// come back from the backup from before the first change.
    private func rollBack(_ ledger: WriteLedger, store: SnapshotStore) {
        guard (try? device.volume.ensureStillMounted()) != nil else { return }
        for url in ledger.placed { try? environment.files.removeItem(at: url) }
        if let backup = ledger.backup { try? store.restore(backup, to: device, include: SnapshotStore.artworkOnly) }
    }
}
