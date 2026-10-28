import SwiftUI
import AppKit
import ClickwillModel
import ITDBKit

/// Settings. For now just one: how long we keep backups
/// (`BackupSettings`), and next to it, how much space the backups really take (`BackupUsage`).
struct SettingsView: View {
    @Environment(LibraryModel.self) private var model
    @AppStorage(BackupSettings.daysKey) private var days = BackupSettings.defaultDays

    @State private var usage: BackupUsage?
    @State private var busy = false
    @State private var lastPrune: String?

    var body: some View {
        // The native macOS 27 settings window: a grouped Form, like System Settings.
        Form {
            Section {
                Picker("Keep backups for", selection: $days) {
                    ForEach(BackupSettings.dayChoices, id: \.self) { choice in
                        Text(Self.label(days: choice)).tag(choice)
                    }
                }
            } header: {
                Text("Backups")
            } footer: {
                Text("""
                    Before every write, Clickwill copies the iPod's database and covers \
                    to this Mac. Music is never copied: the files on the iPod stay \
                    where they are. \(days == BackupSettings.forever
                        ? "Nothing is ever deleted. The folder grows with every write that changes a cover."
                        : "Older copies are deleted after a write. The three most recent are always kept, whatever their age, so after a break you still have something to go back to.")
                    """)
            }

            Section("On This Mac") {
                LabeledContent("Backups of this iPod") {
                    if let usage {
                        Text("\(usage.count) \(usage.count == 1 ? "copy" : "copies") · \(ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file))")
                            .monospacedDigit()
                    } else {
                        Text(busy ? "Measuring…" : "No iPod connected").foregroundStyle(.secondary)
                    }
                }
                if let usage, usage.expired > 0 {
                    LabeledContent("Past the limit") {
                        Text("\(usage.expired)").monospacedDigit().foregroundStyle(.orange)
                    }
                }
                HStack {
                    if let lastPrune {
                        Label(lastPrune, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Refresh") { Task { await refresh() } }
                        .disabled(busy)
                    Button("Delete Old Copies Now") { pruneNow() }
                        .disabled(busy || (usage?.expired ?? 0) == 0)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .task { await refresh() }
        .onChange(of: days) { model.backupRetention = BackupSettings.retention(days: days) }
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        usage = BackupUsage.measure(device: model.device, store: try? model.environment.backups(),
                                    retention: BackupSettings.retention(days: days))
    }

    private func pruneNow() {
        guard let device = model.device, let store = try? model.environment.backups() else { return }
        let removed = store.prune(deviceGUID: device.identity,
                                  retention: BackupSettings.retention(days: days))
        lastPrune = removed.isEmpty
            ? "Nothing was old enough to delete."
            : "Deleted \(removed.count) \(removed.count == 1 ? "copy" : "copies")."
        Task { await refresh() }
    }

    private static func label(days: Int) -> String {
        switch days {
        case BackupSettings.forever: return "Forever"
        case 365: return "1 year"
        default: return "\(days) days"
        }
    }
}
