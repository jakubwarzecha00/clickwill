import SwiftUI
import ClickwillModel

/// The list of pending changes, with removals highlighted, and the write button.
struct PendingChangesSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var applying = false
    /// After a successful write the sheet turns into a report, instead of closing
    /// and opening a system alert - that one did not fit the rest and mixed
    /// the backup identifier with the description of repairs in one paragraph.
    @State private var report: WriteReport?

    init(report: WriteReport? = nil) {
        _report = State(initialValue: report)
    }
    @State private var failure: String?

    var body: some View {
        // A native macOS 27 sheet, like Add Songs: the system background, Form sections
        // in the grouped style, buttons in the standard places of the bar.
        NavigationStack {
            Group {
                if let report {
                    WriteReportView(report: report)
                } else {
                    changesView
                }
            }
            .navigationTitle(report == nil ? "Pending Changes" : "Written to the iPod")
            .toolbar { toolbar }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 360, idealHeight: 440)
        .sheetKeyFocus()
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if report != nil {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        } else {
            ToolbarItem(placement: .destructiveAction) {
                Button("Discard All", role: .destructive) {
                    Task { await model.discardChanges(); dismiss() }
                }
                .disabled(!model.hasPendingChanges || applying)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(applying ? "Writing…" : "Write to iPod", action: apply)
                    .disabled(!canApply || applying)
            }
        }
    }

    private var changesView: some View {
        Form {
            if model.changes.log.isEmpty {
                Section {
                    ContentUnavailableView("Nothing to Write", systemImage: "checkmark.circle",
                                           description: Text("The iPod matches what you see.").foregroundStyle(.secondary))
                }
            } else {
                Section {
                    ForEach(model.changes.log) { change in
                        // The icon carries the only thing that must be seen
                        // before the write: whether this change can be undone.
                        Label {
                            Text(change.summary).lineLimit(3)
                        } icon: {
                            Image(systemName: change.isDestructive ? "trash" : "circle.fill")
                                .foregroundStyle(change.isDestructive ? .red : .accentColor)
                                .imageScale(change.isDestructive ? .medium : .small)
                        }
                    }
                } header: {
                    Text(model.changes.log.count == 1 ? "1 change" : "\(model.changes.log.count) changes")
                }
            }
            Section {
                notice
                if applying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Writing to the iPod…").foregroundStyle(.secondary)
                    }
                }
                if let failure {
                    Label(failure, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// The write state: what blocks it, or what will happen when you agree.
    @ViewBuilder private var notice: some View {
        if let preflight = model.preflight(), !preflight.isClear {
            Label(preflight.blocking.map(ErrorPresenter.message(for:)).joined(separator: " · "),
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if !model.isWritable {
            Label(model.writeUnavailable.map(ErrorPresenter.message(for:)) ?? "Connect an iPod to write changes.", systemImage: "lock")
                .foregroundStyle(.secondary)
        } else {
            Label("Writing takes a fresh backup first, verifies the database twice, and only then replaces it on the iPod.",
                  systemImage: "shield.lefthalf.filled")
                .foregroundStyle(.secondary)
        }
    }

    private var canApply: Bool {
        model.isWritable && model.hasPendingChanges && (model.preflight()?.isClear ?? false)
    }

    private func apply() {
        applying = true
        failure = nil
        Task {
            do {
                // The change descriptions are taken before the write - after it the queue is empty.
                let changes = model.changes.log.map(\.summary)
                let outcome = try await model.apply()
                withAnimation(.easeOut(duration: 0.2)) {
                    report = WriteReport(changes: changes, outcome: outcome)
                }
            } catch {
                failure = "Nothing was written. The iPod is unchanged. \(ErrorPresenter.message(for: error))"
            }
            applying = false
        }
    }
}
