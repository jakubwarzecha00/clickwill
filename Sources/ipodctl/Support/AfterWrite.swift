import ITDBKit
import ClickwillModel

/// One uniform message after a write - every command that changes the iPod ends the same way.
func announce(_ outcome: WriteOutcome) {
    let result = outcome.result
    print("\n  Written. Backup: \(result.snapshot.id)")
    print("  Database size: \(result.byteCount) B")
    if result.mergedPlayCounts > 0 {
        print("  Pending plays merged: \(result.mergedPlayCounts) tracks" + (result.playCountsRemoved ? ", Play Counts file deleted." : "."))
    }
    if !result.playCountsRemoved {
        print("  WARNING: the database was written, but the Play Counts file could not be deleted - remove it by hand before the next write,")
        print("           otherwise the same plays will be counted a second time.")
    }
    for (label, count) in [("Added tracks", outcome.addedTracks), ("Transcoded files", outcome.convertedFiles),
                           ("Restored files", outcome.restoredFiles), ("Artwork", outcome.coversWritten),
                           ("Deleted files", outcome.deletedFiles)] where count > 0 {
        print("  \(label): \(count)")
    }
    let problems = outcome.additionProblems + outcome.conversionProblems + outcome.restoreProblems
        + outcome.coversFailed + outcome.oldFileProblems
    for problem in problems { print("  WARNING: \(problem)") }
    for url in outcome.undeletedFiles { print("  WARNING: \(url.lastPathComponent) not deleted - will retry on the next write") }
    for url in outcome.keptFiles { print("  WARNING: \(url.path) not deleted - it is not a regular file in Music") }
    printRepairs(outcome.repairs)
    print(outcome.orderIntentSaved ? "  Order intent saved." : "  WARNING: the order intent could not be saved.")
}

/// The repairs the transaction made during the write (`RepairPipeline`).
private func printRepairs(_ repairs: RepairPipeline.Report) {
    let done = [
        ("artwork markers 0x7E", repairs.artworkMarkers),
        ("artwork coverage", repairs.coverage.count),
        ("image sizes", repairs.artworkSources.values.reduce(0, +)),
        ("image pointers 0x160", repairs.artworkIdentifiers.values.reduce(0, +)),
        ("image records per track", repairs.trackImages.values.reduce(0, +)),
        ("second identifiers 0xA8", repairs.secondaryIdentifiers.values.reduce(0, +)),
        ("album records", repairs.albumIdentities.count),
    ].filter { $0.1 > 0 }
    if !done.isEmpty { print("  Repairs during the write: " + done.map { "\($0.0) \($0.1)" }.joined(separator: ", ")) }
    for problem in repairs.problems { print("  WARNING: a repair did not go through: \(problem)") }
}
