import Foundation
import CoreGraphics
import ITDBKit

/// The ledger of one write: what the phases did on the iPod and what came of it.
///
/// Each phase writes itself in here, so `WriteTransaction.run()` does not glue together
/// results of different shapes, and a new phase is a new type and one line in the list
/// of phases. The ledger produces the report (`WriteOutcome`) and the queue after the write
/// (`ChangeSet.remaining(after:)`).
struct WriteLedger {

    // MARK: - For rollback and after the write

    /// Files put on the iPod before the database - to delete if the database write fails.
    var placed: [URL] = []
    /// Old files (from before a conversion or replacement) - to delete after the database write.
    var oldFiles: [URL] = []
    /// The backup from before the first change on the iPod - artwork comes back
    /// from it if the write fails.
    var backup: Snapshot?
    /// Tasks that went in, and files that were not deleted.
    var completed = ChangeSet.Completed()
    /// Artwork of new albums by track `persistentID` - for the preview in the app.
    var coverImages: [UInt64: CGImage] = [:]
    /// Whether `ArtworkDB` on the iPod changed.
    var artworkChanged = false
    /// Albums that got artwork in this write - on an unconfirmed model the artwork steps of
    /// `RepairPhase` run only for these and for albums with added songs.
    var artworkAlbums: Set<String> = []

    // MARK: - For the report (`WriteOutcome`)

    var coversWritten = 0
    /// "album: error".
    var coversFailed: [WriteProblem] = []
    var convertedFiles = 0
    var conversionProblems: [WriteProblem] = []
    var restoredFiles = 0
    var restoreProblems: [WriteProblem] = []
    var addedTracks = 0
    var additionProblems: [WriteProblem] = []
    var deletedFiles = 0
    /// Files the rule did not allow to be deleted (a folder, a link, something
    /// outside `Music`) - they stay on the iPod and do not come back to the queue. Retries
    /// are in `completed.deletionsToRetry`.
    var keptFiles: [URL] = []
    var oldFileProblems: [WriteProblem] = []
    var repairs = RepairPipeline.Report()

    /// Whether any track got a new file (conversion, restore, replacement).
    var filesReplaced: Bool { convertedFiles > 0 || restoredFiles > 0 }

    /// The backup before the first change on the iPod - once per write.
    mutating func backUpOnce(_ device: IPodDevice, in store: SnapshotStore, reason: SnapshotReason, note: String) throws {
        if backup == nil { backup = try store.capture(from: device, reason: reason, note: note) }
    }

    mutating func coverFailed(_ album: String, _ error: any Error) {
        coversFailed.append(WriteProblem(album, .error(error)))
    }
}

/// A write phase before the database: it changes the library in memory, and what it did on
/// the iPod it writes into the ledger. A failed request goes into the ledger and the phase goes
/// on; a thrown error stops the whole write and starts the rollback.
protocol WritePhase {
    func run(_ library: inout ITLibrary, on device: IPodDevice, ledger: inout WriteLedger) async throws
}
