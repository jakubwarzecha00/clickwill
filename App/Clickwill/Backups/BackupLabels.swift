import Foundation
import ITDBKit

/// Human labels for backups - from the backup's reason (`Snapshot.effectiveReason`),
/// not from the note, which is only for humans.
enum BackupLabels {
    static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today at \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func reason(_ backup: Snapshot) -> String {
        switch backup.effectiveReason {
        case .manual: "Made by hand"
        case .beforeRestore: "Before restoring a backup"
        case .beforeFiles: "Before adding or changing files"
        case .beforeArtworkRepair: "Before fixing covers"
        case .beforeWrite(let changes?): "Before writing \(changes) \(changes == 1 ? "change" : "changes")"
        case .beforeWrite(nil): "Before a write"
        case nil: "Automatic backup"
        }
    }
}
