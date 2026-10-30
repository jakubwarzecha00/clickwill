import Foundation
import ITDBKit

/// Repairs on every write (`RepairPipeline`) - the last phase before the database,
/// on the library with all changes and with `ArtworkDB` after the new artwork.
/// Before the first write of `ArtworkDB` it takes a backup, if the write
/// did not take one earlier.
///
/// On an unconfirmed model (`IPodDevice.writesOutsideConfirmedModels`) only for the albums this
/// write changed artwork in or added songs to, and only the steps that make that artwork show:
/// the other repairs change bytes the user didn't ask for, by rules measured on other models.
struct RepairPhase: WritePhase {
    /// Merged duplicates, `persistentID` of the removed one -> the kept one.
    let artworkOwnerRedirects: [UInt64: UInt64]
    /// Albums whose artwork is replaced after the database write (`AfterWritePhase`) - their
    /// songs need the pointers too, e.g. an album added before 0.4.1 without them.
    let replacedArtwork: Set<String>
    let store: SnapshotStore

    func run(_ library: inout ITLibrary, on device: IPodDevice, ledger: inout WriteLedger) {
        var scope: Set<String>?
        if device.writesOutsideConfirmedModels {
            // Songs not in the database on the disk yet are this write's additions.
            let onDisk = Set(((try? device.readLibrary())?.tracks ?? []).map(\.uniqueID))
            let added = library.tracks.filter { !onDisk.contains($0.uniqueID) }.map { $0.album ?? "" }
            scope = ledger.artworkAlbums.union(added).union(replacedArtwork)
            guard scope?.isEmpty == false else { return }
        }
        let repaired = RepairPipeline.run(library, on: device, artworkOwnerRedirects: artworkOwnerRedirects, albums: scope) {
            try ledger.backUpOnce(device, in: store, reason: .beforeArtworkRepair, note: "Clickwill: before artwork repair")
        }
        library = repaired.library
        ledger.repairs = repaired.report
        if repaired.report.wroteArtworkDB { ledger.artworkChanged = true }
    }
}
