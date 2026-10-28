import SwiftUI
import AppKit
import ClickwillModel
import ITDBKit

/// Entries pointing to a file that does not exist - and a way to give them that file
/// back.
///
/// An entry without a file is not the same as a file in the wrong format. That one the iPod knows
/// and skips; this one does not exist at all. That is why we do not hook into the format
/// warning, but have our own dialog - and the file chosen here still
/// goes through the same compatibility verdict and, if needed, through a conversion
/// to the highest format the given iPod model plays.
///
/// Nothing from here reaches the device. Confirming adds items to the list
/// of pending changes, like any other edit.
struct MissingFilesSheet: View {
    let album: AlbumCard
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The file chosen for an entry; the key is the track's `uniqueID`.
    @State private var picks: [UInt32: ImportCandidate] = [:]
    /// Previewing the chosen file - before we put it under an existing entry.
    @State private var preview = PreviewPlayer()
    @State private var scanning = false
    @State private var problem: String?
    /// The folder we last matched from - for the message after the scan.
    @State private var matchedFrom: String?
    @State private var matchedCount: Int?

    private var rows: [TrackRow] { model.tracks(of: album).filter(\.fileMissing) }
    private var chosen: Int { picks.count }
    private var converting: Int { picks.values.filter(\.needsConversion).count }

    var body: some View {
        // A native macOS 27 sheet, like Add Songs: the title in the bar, a grouped
        // Form, Cancel and Restore in their standard places.
        NavigationStack {
            Group {
                if scanning {
                    ProgressView("Reading the folder…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    ContentUnavailableView {
                        Label("Every Song Has Its File", systemImage: "checkmark.circle")
                    } description: {
                        Text("Nothing in this album is missing.").foregroundStyle(.secondary)
                    }
                } else {
                    form
                }
            }
            .navigationTitle("Entries Without a File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(chosen == 1 ? "Restore 1 Entry" : "Restore \(chosen) Entries") { commit() }
                        .disabled(chosen == 0)
                }
            }
        }
        .frame(minWidth: 680, idealWidth: 740, minHeight: 480, idealHeight: 560)
        .sheetKeyFocus()
        .onDisappear { preview.stop() }
    }

    // MARK: - Parts

    private var form: some View {
        Form {
            Section {
                LabeledContent("Album", value: "\(album.displayTitle) · \(album.displayArtist)")
                HStack {
                    if let matchedFrom, let matchedCount {
                        Label(matchedCount == 0
                              ? "Nothing in \(matchedFrom) matched these titles or track numbers."
                              : "Matched \(matchedCount) of \(rows.count) from \(matchedFrom).",
                              systemImage: matchedCount == 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(matchedCount == 0 ? Color.orange : Color.green)
                    }
                    Spacer()
                    Button("Match from a Folder…") { matchFolder() }
                }
            } footer: {
                // The color explicitly: the window imposes Theme.fg on all texts, footers included.
                Text("""
                    These songs are in the iPod's database, but the audio file they point \
                    at is gone. The iPod skips them. Point each one at a file on this Mac \
                    and it comes back: the song keeps its play count, its place in the \
                    album and its cover.
                    """)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(rows) { row in
                    MissingFileRow(row: row, pick: picks[row.id], preview: preview,
                                   choose: { choose(for: row) },
                                   clear: {
                                       if let pick = picks[row.id], preview.isLoaded(pick.id) { preview.stop() }
                                       picks[row.id] = nil
                                   })
                }
            } header: {
                Text(rows.count == 1 ? "1 Entry" : "\(rows.count) Entries")
            } footer: {
                // The limits by which we judge files depend on the model - and the model
                // cannot always be read. When it is assumed, we say so plainly.
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.capabilities.isAssumed
                         ? "Checked against \(model.capabilities.name). Exact model unknown."
                         : "Checked against \(model.capabilities.name).")
                    if converting > 0 {
                        Text("\(converting) will be converted on the way. The file on this Mac isn't touched.")
                    }
                }
                .foregroundStyle(.secondary)
            }
            if let problem {
                Section {
                    Label(problem, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func choose(for row: TrackRow) {
        guard let url = FilePanels.chooseAudioFile(message: "Choose the audio file for “\(row.displayTitle)”.",
                                                   prompt: "Use This File") else { return }
        Task {
            scanning = true
            defer { scanning = false }
            guard let candidate = await model.inspect(url) else {
                problem = "\(url.lastPathComponent) isn't an audio file Clickwill can read. Choose an MP3, AAC, Apple Lossless, WAV, AIFF or FLAC file."
                return
            }
            if candidate.isHopeless {
                problem = "\(url.lastPathComponent): \(candidate.verdict.reason ?? "the iPod cannot play this")"
                return
            }
            problem = nil
            picks[row.id] = candidate
        }
    }

    private func matchFolder() {
        guard let directory = FilePanels.chooseFolder(message: "Choose the folder holding this album's files.",
                                                      prompt: "Match") else { return }
        Task {
            scanning = true
            defer { scanning = false }
            let found = await model.matchFiles(in: directory, to: rows)
            // A choice made by hand stays - matching only fills the gaps.
            var added = 0
            for (id, candidate) in found where picks[id] == nil && !candidate.isHopeless {
                picks[id] = candidate
                added += 1
            }
            matchedFrom = directory.lastPathComponent
            matchedCount = added
            problem = nil
        }
    }

    private func commit() {
        let all = rows
        var failures: [String] = []
        for row in all {
            guard let candidate = picks[row.id] else { continue }
            do { try model.importFile(candidate, for: row, in: album) }
            catch { failures.append(ErrorPresenter.message(for: error)) }
        }
        guard failures.isEmpty else { problem = failures.joined(separator: "\n"); return }
        dismiss()
    }
}

/// One entry without a file and what was chosen for it.
private struct MissingFileRow: View {
    let row: TrackRow
    let pick: ImportCandidate?
    @Bindable var preview: PreviewPlayer
    let choose: () -> Void
    let clear: () -> Void

    /// The length difference at which a warning is worth it. A few seconds is usually another
    /// release of the same recording; half a minute is usually a different track.
    private var mismatch: String? {
        guard let pick, pick.duration > 0, row.duration > 0 else { return nil }
        let delta = abs(pick.duration - row.duration)
        guard delta > 5 else { return nil }
        return "the file is \(pick.duration.clockLabel), the entry says \(row.duration.clockLabel)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(row.number == 0 ? "–" : "\(row.number)")
                .frame(width: 26, alignment: .trailing)
                .foregroundStyle(.secondary).monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayTitle).lineLimit(1)
                status
            }
            Spacer(minLength: 8)
            // Previewing makes sense only once a file is chosen - that is the question
            // "am I putting the right recording under this entry".
            if let pick {
                PreviewButton(id: pick.id, url: pick.url, preview: preview)
            }
            Text(row.duration.clockLabel)
                .foregroundStyle(.secondary).monospacedDigit()
            Button(pick == nil ? "Choose…" : "Change…", action: choose)
            if pick != nil {
                Button("Leave Without a File", systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Leave this entry without a file")
            }
        }
    }

    @ViewBuilder private var status: some View {
        if let pick {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(pick.fileName).font(.subheadline).lineLimit(1)
                    Text(pick.formatLabel).font(.caption).foregroundStyle(.secondary)
                }
                if let target = pick.target {
                    Text("will be converted to \(target.label)")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let mismatch {
                    Text(mismatch).font(.caption).foregroundStyle(.orange)
                }
            }
        } else {
            Text("No file chosen, the iPod skips this song")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
