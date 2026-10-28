import SwiftUI
import ITDBKit
import ClickwillModel

/// The list of the connected iPod's backups, and restoring them.
///
/// Restoring existed in the core and in `ipodctl`, but not in the app - backups
/// were made on every write and there was no way to use them.
struct BackupsScreen: View {
    @Environment(LibraryModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @State private var backups: [Snapshot] = []
    @State private var selectedID: String?
    @State private var preview: BackupPreview?
    @State private var previewError: String?
    @State private var phase: Phase = .browsing

    enum Phase: Equatable {
        case browsing
        case confirming
        case restoring
        case restored(savedAs: Date)
        case failed(String)
    }

    private var selected: Snapshot? { backups.first { $0.id == selectedID } }

    var body: some View {
        // A native layout: the list of backups on the left (a List with selection),
        // the details on the right in a grouped Form, the system empty state, an on-demand
        // backup in the toolbar.
        Group {
            if backups.isEmpty {
                ContentUnavailableView {
                    Label("No Backups Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    // The color explicitly: the window imposes Theme.fg on all texts.
                    Text("Clickwill makes one automatically before every write. Each one is the iPod as it was just before that write.")
                        .foregroundStyle(.secondary)
                } actions: {
                    if model.device != nil { Button("Back Up Now", action: backUpNow) }
                }
            } else {
                HStack(spacing: 0) {
                    list
                    Divider()
                    detail
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // An on-demand backup - before another program touches the iPod.
                Button("Back Up Now", systemImage: "externaldrive.badge.plus", action: backUpNow)
                    .disabled(model.device == nil || model.writesBlocked || phase == .restoring)
                    .help("Saves the iPod's library and covers as they are right now. Reads the iPod; writes nothing to it.")
            }
        }
        .alert("Replace the library on the iPod with this backup?", isPresented: confirming) {
            Button("Cancel", role: .cancel) { phase = .browsing }
            Button("Restore") { if let selected { Task { await restore(selected) } } }
        } message: {
            Text("Clickwill saves the current state as a new backup first, so this can be undone.")
        }
        .onAppear(perform: reload)
        .task(id: selectedID) { await loadPreview() }
    }

    private var confirming: Binding<Bool> {
        Binding(get: { phase == .confirming }, set: { if !$0, phase == .confirming { phase = .browsing } })
    }

    // MARK: - List

    private var list: some View {
        List(backups, id: \.id, selection: $selectedID) { backup in
            VStack(alignment: .leading, spacing: 2) {
                Text(BackupLabels.when(backup.createdAt))
                Text(BackupLabels.reason(backup)).font(.subheadline).foregroundStyle(.secondary)
                    .help(backup.note ?? "")
            }
            .padding(.vertical, 2)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .disabled(phase == .restoring)
        .onChange(of: selectedID) { phase = .browsing }
        .frame(width: 300)
    }

    // MARK: - Details

    @ViewBuilder private var detail: some View {
        if let selected {
            Form {
                Section {
                    LabeledContent("Made", value: BackupLabels.when(selected.createdAt))
                    LabeledContent("Why", value: BackupLabels.reason(selected))
                }
                content(for: selected)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView("Choose a Backup", systemImage: "clock.arrow.circlepath",
                                   description: Text("See what restoring it would change.").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder private func content(for snapshot: Snapshot) -> some View {
        switch phase {
        case .restored(let savedAs):
            Section {
                Label("Backup restored", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Eject the iPod to see it on the device.")
                Text("The library as it was a moment ago is saved as the backup from \(BackupLabels.when(savedAs)). Restore that one to undo.")
                    .foregroundStyle(.secondary)
                Button("Done") { phase = .browsing; reload() }
            }
        case .failed(let reason):
            Section {
                Label("Nothing was restored", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                Text(reason).textSelection(.enabled)
                Text("The iPod is as it was before you clicked.").foregroundStyle(.secondary)
                Button("OK") { phase = .browsing }
            }
        case .restoring:
            Section {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Restoring: checking the backup, saving the current state, then writing…").foregroundStyle(.secondary)
                }
            }
        case .browsing, .confirming:
            if let previewError {
                Section { Label(previewError, systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
            } else if let preview, preview.snapshot.id == snapshot.id {
                facts(preview)
                restoreSection
            } else {
                Section { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder private func facts(_ preview: BackupPreview) -> some View {
        // 1. What the write made right after this backup changed.
        Section {
            if preview.writeAfter.isEmpty {
                Text("No songs, names or album order changed. That write touched only play counts, covers or other files.")
                    .foregroundStyle(.secondary)
            } else {
                DiffList(diff: preview.writeAfter, direction: .forward)
            }
        } header: {
            Text("What the Next Write Changed")
        } footer: {
            Text(preview.writeAfterUntil.map { "Compared with the backup from \(BackupLabels.when($0.createdAt).lowercasedFirst)." }
                 ?? "Compared with the iPod as it is now.")
                .foregroundStyle(.secondary)
        }

        // 2. What the restore will undo.
        Section {
            if preview.restoring.isEmpty && preview.withoutFile.isEmpty {
                Text("The library would stay exactly as it is now.").foregroundStyle(.secondary)
            } else {
                if !preview.withoutFile.isEmpty {
                    songGroup("\(songs(preview.withoutFile.count)) would come back without a file",
                              detail: "Their files were erased or replaced after this backup.",
                              icon: "exclamationmark.triangle", preview.withoutFile)
                }
                DiffList(diff: preview.restoring, direction: .restore)
            }
        } header: {
            Text("If You Restore It")
        } footer: {
            Text("\(preview.songCount) songs in \(preview.albumCount) albums. Play counts stay as they are now.")
                .foregroundStyle(.secondary)
        }
    }

    private func songGroup(_ title: String, detail: String, icon: String, _ songs: [LibraryDiff.Song]) -> some View {
        DisclosureGroup {
            Text(detail).foregroundStyle(.secondary)
            ForEach(songs, id: \.persistentID) { song in
                Text("\(song.title) · \(song.album)").lineLimit(1)
            }
        } label: {
            Label(title, systemImage: icon).foregroundStyle(.orange)
        }
    }

    private var restoreSection: some View {
        let blocked = restoreBlocker
        return Section {
            HStack {
                Spacer()
                Button("Restore This Backup…") { phase = .confirming }
                    .disabled(blocked != nil)
            }
        } footer: {
            if let blocked { Text(blocked).foregroundStyle(.secondary) }
        }
    }

    private func songs(_ n: Int) -> String { n == 1 ? "1 song" : "\(n) songs" }

    /// Why restoring is impossible right now - or `nil`.
    private var restoreBlocker: String? {
        guard let device = model.device else { return "Connect the iPod this backup came from." }
        if !device.supportsWriting { return ErrorPresenter.readOnlyMessage(device.readOnlyReason) }
        if model.hasPendingChanges {
            return "Write or discard the \(model.changes.log.count) pending \(model.changes.log.count == 1 ? "change" : "changes") first. Restoring replaces the library they were made on."
        }
        if let issue = model.preflight()?.blocking.first { return ErrorPresenter.message(for: issue) }
        return nil
    }

    // MARK: - Actions

    private func reload() {
        backups = model.backups()
        if selectedID == nil || !backups.contains(where: { $0.id == selectedID }) {
            selectedID = backups.first?.id
        }
    }

    private func backUpNow() {
        do {
            let made = try model.backUpNow()
            reload()
            selectedID = made.id
        } catch {
            phase = .failed("The backup couldn't be made. \(ErrorPresenter.message(for: error))")
        }
    }

    private func loadPreview() async {
        preview = nil
        previewError = nil
        guard let selected else { return }
        do { preview = try await model.preview(selected) }
        catch { previewError = "This backup can't be read. \(ErrorPresenter.message(for: error))" }
    }

    private func restore(_ snapshot: Snapshot) async {
        phase = .restoring
        // The player holds a file from the iPod - just like when ejecting.
        playback.stop()
        do {
            let before = try await model.restoreBackup(snapshot)
            phase = .restored(savedAs: before.createdAt)
        } catch {
            phase = .failed(ErrorPresenter.message(for: error))
        }
    }
}
