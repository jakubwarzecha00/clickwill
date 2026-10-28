import Foundation
import ITDBKit

/// Repairs on every write (`RepairPipeline`) - the last phase before the database,
/// on the library with all changes and with `ArtworkDB` after the new artwork.
/// Before the first write of `ArtworkDB` it takes a backup, if the write
/// did not take one earlier.
struct RepairPhase: WritePhase {
    /// Merged duplicates, `persistentID` of the removed one -> the kept one.
    let artworkOwnerRedirects: [UInt64: UInt64]
    let store: SnapshotStore

    func run(_ library: inout ITLibrary, on device: IPodDevice, ledger: inout WriteLedger) {
        let repaired = RepairPipeline.run(library, on: device, artworkOwnerRedirects: artworkOwnerRedirects) {
            try ledger.backUpOnce(device, in: store, reason: .beforeArtworkRepair, note: "Clickwill: before artwork repair")
        }
        library = repaired.library
        ledger.repairs = repaired.report
        if repaired.report.wroteArtworkDB { ledger.artworkChanged = true }
    }
}
