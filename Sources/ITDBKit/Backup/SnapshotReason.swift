import Foundation

/// Why a backup was made - stored in the manifest next to the note.
///
/// The note (`Snapshot.note`) is for humans and may say anything;
/// the reason decides what the backup is called in the app. That way changing
/// a word in the note does not silently change the label on the backups screen.
public enum SnapshotReason: Codable, Sendable, Hashable {
    /// On demand: the button in the app, `ipodctl backup`.
    case manual
    /// Before a database write. `changes`: how many changes from the list went into
    /// this write; `nil` when the write does not come from the change list (`ipodctl`).
    case beforeWrite(changes: Int?)
    /// Before files on the iPod: artwork, conversions, added tracks,
    /// files for entries.
    case beforeFiles
    /// Before an artwork repair during a write.
    case beforeArtworkRepair
    /// Before restoring another backup.
    case beforeRestore
}

extension SnapshotReason {

    /// The reason from the note, which versions up to 0.2.5 stored instead of a reason -
    /// the only place that reads notes. `nil`: the note says nothing
    /// (e.g. a description from `ipodctl`).
    ///
    /// Those versions wrote their notes in Polish, so the phrases matched below
    /// are Polish on purpose: they are data found in existing backups.
    init?(legacyNote note: String?) {
        guard let note = note?.lowercased() else { return nil }
        if note.contains("kopia reczna") { self = .manual; return }
        if note.contains("przywroceniem kopii") { self = .beforeRestore; return }
        if note.contains("naprawa okladek") { self = .beforeArtworkRepair; return }
        // Restoring files and conversion are older names for the same step.
        if ["przywroceniem plikow", "konwersja", "zmianami plikow"].contains(where: note.contains) {
            self = .beforeFiles; return
        }
        if note.contains("zmian"), let count = note.split(separator: " ").compactMap({ Int($0) }).first {
            self = .beforeWrite(changes: count); return
        }
        if note.contains("zapisem") { self = .beforeWrite(changes: nil); return }
        return nil
    }
}

extension Snapshot {
    /// The reason from the manifest, or, for backups from before reasons existed, read from the note.
    public var effectiveReason: SnapshotReason? { reason ?? SnapshotReason(legacyNote: note) }
}
