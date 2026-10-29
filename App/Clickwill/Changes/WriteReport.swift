import SwiftUI
import ClickwillModel

/// The result of a write, broken down into what the user may want to read.
///
/// It replaces a system alert with a single paragraph in which these stood side by side:
/// the backup identifier, the number of database bytes and the description of the 0x160 field repair.
/// Here each thing has its own place and weight - first what needs
/// attention, then what you asked for, and finally what the app fixed by itself.
struct WriteReport: Identifiable {
    let id = UUID()
    /// Changes from the queue, in the same words in which they were queued.
    let changes: [String]
    /// Fixes the app made by itself while writing.
    let repairs: [String]
    /// Things that failed or need the user to act.
    let problems: [String]
    let backupDate: Date
    let backupBytes: Int64

    /// A sample report for screenshots (`--demo --screen write-report`) - writing in demo mode is blocked.
    static var demo: WriteReport {
        WriteReport(changes: ["Add 6 songs (1 album, 568.1 MB, 6 to be converted first)", "Change the cover of Low Tide Radio"],
                    repairs: ["Converted 6 files to a format the iPod plays", "Kept the plays from the iPod for 12 songs"],
                    problems: [], backupDate: Date(), backupBytes: 4_812_000)
    }

    private init(changes: [String], repairs: [String], problems: [String], backupDate: Date, backupBytes: Int64) {
        self.changes = changes; self.repairs = repairs; self.problems = problems
        self.backupDate = backupDate; self.backupBytes = backupBytes
    }

    init(changes: [String], outcome: WriteOutcome) {
        self.changes = changes
        backupDate = outcome.result.snapshot.createdAt
        backupBytes = outcome.result.snapshot.totalBytes

        var repairs: [String] = []
        func songs(_ n: Int) -> String { n == 1 ? "1 song" : "\(n) songs" }
        func albums(_ names: some Collection<String>) -> String {
            let sorted = names.sorted()
            guard sorted.count > 3 else { return sorted.joined(separator: ", ") }
            return sorted.prefix(3).joined(separator: ", ") + " and \(sorted.count - 3) more"
        }
        func total(_ map: [String: Int]) -> Int { map.values.reduce(0, +) }

        if outcome.result.mergedPlayCounts > 0 {
            repairs.append("Kept the plays from the iPod for \(songs(outcome.result.mergedPlayCounts))")
        }
        if outcome.convertedFiles > 0 {
            repairs.append("Converted \(outcome.convertedFiles) \(outcome.convertedFiles == 1 ? "file" : "files") to a format the iPod plays")
        }
        if !outcome.repairs.artworkIdentifiers.isEmpty {
            repairs.append("Linked \(songs(total(outcome.repairs.artworkIdentifiers))) to their album cover (\(albums(outcome.repairs.artworkIdentifiers.keys)))")
        }
        if !outcome.repairs.artworkSources.isEmpty {
            repairs.append("Fixed the cover of \(songs(total(outcome.repairs.artworkSources))) (\(albums(outcome.repairs.artworkSources.keys)))")
        }
        if outcome.repairs.artworkMarkers > 0 {
            repairs.append("Made the cover show again on \(songs(outcome.repairs.artworkMarkers))")
        }
        if !outcome.repairs.trackImages.isEmpty {
            repairs.append("Gave \(songs(total(outcome.repairs.trackImages))) their album cover, so it shows while they play (\(albums(outcome.repairs.trackImages.keys)))")
        }
        if !outcome.repairs.coverage.isEmpty {
            repairs.append("Made the cover show on every song of \(albums(outcome.repairs.coverage))")
        }
        if !outcome.repairs.secondaryIdentifiers.isEmpty {
            repairs.append("Fixed a missing library detail on \(songs(total(outcome.repairs.secondaryIdentifiers)))")
        }
        if !outcome.repairs.albumIdentities.isEmpty {
            let n = outcome.repairs.albumIdentities.count
            repairs.append("Kept \(n) \(n == 1 ? "album" : "albums") from being mixed up with another one")
        }
        if outcome.prunedBackups > 0 {
            repairs.append("Removed \(outcome.prunedBackups) old \(outcome.prunedBackups == 1 ? "backup" : "backups") older than the time set in Settings › Backups")
        }
        self.repairs = repairs

        var problems: [String] = []
        if !outcome.result.playCountsRemoved {
            problems.append("The Play Counts file couldn't be removed. Delete it before the next write, or those plays will be counted twice.")
        }
        if !outcome.undeletedFiles.isEmpty {
            problems.append("\(outcome.undeletedFiles.count) \(outcome.undeletedFiles.count == 1 ? "file" : "files") couldn't be erased from the iPod and stay queued.")
        }
        for problem in outcome.additionProblems {
            if case .notPlaced(let error) = problem.reason {
                problems.append("Added, but not where you dropped it: \(problem.subject) (\(ErrorPresenter.message(for: error)))")
            } else {
                problems.append("Not added: \(ErrorPresenter.line(problem))")
            }
        }
        problems += outcome.restoreProblems.map { "No file given: \(ErrorPresenter.line($0))" }
        problems += outcome.conversionProblems.map { "Not converted: \(ErrorPresenter.line($0))" }
        problems += outcome.oldFileProblems.map { "Old file kept: \(ErrorPresenter.line($0))" }
        problems += outcome.coversFailed.map { "Cover not written: \(ErrorPresenter.line($0))" }
        problems += outcome.repairs.problems.map(ErrorPresenter.message(for:))
        if !outcome.keptFiles.isEmpty { problems.append(ErrorPresenter.keptFiles(outcome.keptFiles)) }
        if !outcome.orderIntentSaved {
            problems.append("Clickwill couldn't save a copy of the album order on this Mac. The order on the iPod is written.")
        }
        self.problems = problems
    }

    /// "today at 14:14", "yesterday at 9:02", or the full date - instead of
    /// the file identifier, which says the same, only in UTC and with hyphens.
    var backupLabel: String {
        let time = backupDate.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(backupDate) { day = "today at \(time)" }
        else if calendar.isDateInYesterday(backupDate) { day = "yesterday at \(time)" }
        else { day = backupDate.formatted(date: .abbreviated, time: .shortened) }
        return "Saved \(day) · \(ByteCountFormatter.string(fromByteCount: backupBytes, countStyle: .file))"
    }
}

/// The write result in the Pending Changes sheet: a Form in the grouped style, like the rest
/// of the native sheets. The sheet bar provides the Done button.
struct WriteReportView: View {
    let report: WriteReport

    var body: some View {
        Form {
            Section {
                Label {
                    // This is not politeness: the iPod reads the database only on
                    // eject, so before it, it shows the state from before the write.
                    Text("Eject the iPod to see the changes on the device.")
                } icon: {
                    Image(systemName: report.problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(report.problems.isEmpty ? .green : .orange)
                }
            }
            if !report.problems.isEmpty {
                section("Needs Your Attention", report.problems, icon: "exclamationmark.triangle.fill", tint: .orange)
            }
            if !report.changes.isEmpty {
                section("Written", report.changes, icon: "checkmark", tint: .green)
            }
            if !report.repairs.isEmpty {
                section("Also Fixed Along the Way", report.repairs, icon: "wrench.and.screwdriver", tint: .secondary)
            }
            Section {
                LabeledContent("Backup", value: report.backupLabel)
                    .help("Settings › Backups lists every copy and how long they are kept.")
            }
        }
        .formStyle(.grouped)
    }

    private func section(_ title: String, _ lines: [String], icon: String, tint: some ShapeStyle) -> some View {
        Section(title) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Label {
                    Text(line).textSelection(.enabled)
                } icon: {
                    Image(systemName: icon).foregroundStyle(tint)
                }
            }
        }
    }
}
