import Foundation
import ITDBKit

/// What a successful write to the iPod did - for the post-write report and the diagnostic report.
public struct WriteOutcome: Sendable {
    public let result: DatabaseWriteResult
    public var deletedFiles = 0
    /// Files that could not be deleted - they stay in the queue for the next write.
    public var undeletedFiles: [URL] = []
    /// Files the rule did not allow to be deleted (a folder, a link, something
    /// outside `Music`) - they stay on the iPod and do not come back to the queue.
    public var keptFiles: [URL] = []
    public var orderIntentSaved = false
    /// Artwork written: first artwork for albums, artwork of new albums and replacements.
    public var coversWritten = 0
    public var coversFailed: [WriteProblem] = []
    public var convertedFiles = 0
    public var conversionProblems: [WriteProblem] = []
    /// Old files (from before a conversion or a file replacement) that were not deleted.
    public var oldFileProblems: [WriteProblem] = []
    public var addedTracks = 0
    public var additionProblems: [WriteProblem] = []
    /// Entries whose file was restored or replaced.
    public var restoredFiles = 0
    public var restoreProblems: [WriteProblem] = []
    /// Backups deleted after the write because they exceeded the retention time.
    public var prunedBackups = 0
    /// Repairs during the write (`RepairPipeline`).
    public var repairs = RepairPipeline.Report()

    /// The report from the write ledger - the one place where the phases' numbers go into the report.
    init(result: DatabaseWriteResult, ledger: WriteLedger, orderIntentSaved: Bool, prunedBackups: Int) {
        self.result = result
        deletedFiles = ledger.deletedFiles
        undeletedFiles = ledger.completed.deletionsToRetry
        keptFiles = ledger.keptFiles
        self.orderIntentSaved = orderIntentSaved
        coversWritten = ledger.coversWritten
        coversFailed = ledger.coversFailed
        convertedFiles = ledger.convertedFiles
        conversionProblems = ledger.conversionProblems
        oldFileProblems = ledger.oldFileProblems
        addedTracks = ledger.addedTracks
        additionProblems = ledger.additionProblems
        restoredFiles = ledger.restoredFiles
        restoreProblems = ledger.restoreProblems
        self.prunedBackups = prunedBackups
        repairs = ledger.repairs
    }

    /// Lines for the diagnostic report - counts and causes, without titles.
    public var summary: [String] {
        var lines = ["Last write: covers written \(coversWritten), covers failed \(coversFailed.count), "
            + "songs added \(addedTracks), files deleted \(deletedFiles), files converted \(convertedFiles)"]
        // The reason alone, without the album title - the user sends the report.
        lines += coversFailed.map { "  cover failure: \($0.reason)" }
        let repaired = [
            ("artwork markers", repairs.artworkMarkers),
            ("cover counts", repairs.coverage.count),
            ("image sizes", repairs.artworkSources.values.reduce(0, +)),
            ("image links (0x160)", repairs.artworkIdentifiers.values.reduce(0, +)),
            ("image records per track", repairs.trackImages.values.reduce(0, +)),
            ("second identifiers", repairs.secondaryIdentifiers.values.reduce(0, +)),
            ("album records", repairs.albumIdentities.count),
        ].filter { $0.1 > 0 }
        if !repaired.isEmpty {
            lines.append("  repaired while writing: " + repaired.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
        }
        let problems = additionProblems.count + conversionProblems.count + restoreProblems.count + oldFileProblems.count
            + keptFiles.count
        if problems > 0 { lines.append("  other problems: \(problems) (additions, conversions, restores, old files)") }
        lines += repairs.problems.map { "  repair not done: \($0)" }
        return lines
    }
}
