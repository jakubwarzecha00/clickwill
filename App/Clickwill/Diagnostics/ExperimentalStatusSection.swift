import SwiftUI
import ClickwillModel
import ITDBKit

/// The top of Overview for an iPod outside the confirmed models: why it is read-only and the way
/// to Diagnostics, the experimental status, and after the first experimental write the question
/// whether the iPod showed the changes. Technical wording.
struct ExperimentalStatusSection: View {
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window

    var body: some View {
        if let device = model.device {
            if let record = model.experimentalWriteAwaitingAnswer, let grant = model.permissions.grant(for: device) {
                Section("Experimental Write") {
                    Text("Were the changes visible on the iPod?").font(.theme(.row, weight: .semibold))
                    Text("Last experimental write: \(record.date.formatted(date: .abbreviated, time: .shortened)), \(record.changes) \(record.changes == 1 ? "change" : "changes"). The answer is added to the diagnostic report.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Yes") { answer(true, record: record, identity: grant.identity) }
                        Button("No, Something's Wrong") { answer(false, record: record, identity: grant.identity) }
                        Spacer()
                    }
                    Text("Both answers open Send Diagnostic Report with the answer filled in. Nothing is sent automatically. The backup from before the first experimental write is kept in Backups.")
                        .font(.theme(.footnote)).foregroundStyle(.secondary)
                }
            } else if device.writesOutsideConfirmedModels {
                Section("Writing") {
                    LabeledContent(device.writePolicy == .developer ? "Developer Mode" : "Experimental") {
                        Button("Run Diagnostics…") { window.showDiagnostics() }
                    }
                    Text(device.writePolicy == .developer
                         ? "Unconfirmed model, Developer Mode: lists of confirmed families and artwork formats lifted."
                         : "Unconfirmed model. Write-time repairs only for albums changed in the write; deleted files copied to this Mac first.")
                        .font(.theme(.footnote)).foregroundStyle(.secondary)
                }
            } else if !device.supportsWriting {
                Section("Writing") {
                    if device.format.signing == .presumedUnsigned {
                        // An unsigned database the standard policy refuses: a model not confirmed yet.
                        Text("Read-only: \(device.model.name) not confirmed").font(.theme(.row, weight: .semibold))
                        HStack(alignment: .firstTextBaseline) {
                            Text("Run Diagnostics to check this iPod and send the result.").foregroundStyle(.secondary)
                            Spacer()
                            Button("Run Diagnostics…") { window.showDiagnostics() }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        LabeledContent("Read-only") {
                            Button("Run Diagnostics…") { window.showDiagnostics() }
                        }
                        Text(ErrorPresenter.readOnlyMessage(device.readOnlyReason))
                            .font(.theme(.footnote)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Records the answer and opens Send Diagnostic Report with it, so a "no" reaches us as
    /// surely as a "yes".
    private func answer(_ shown: Bool, record: ExperimentalPermissions.WriteRecord, identity: String) {
        model.permissions.answer(shown, for: identity)
        let write = "Experimental write \(record.date.formatted(.iso8601.year().month().day())), \(record.changes) \(record.changes == 1 ? "change" : "changes")"
        window.showSendReport(comment: shown
            ? "\(write): the iPod showed the changes."
            : "\(write): the iPod did not show the changes as expected. What the iPod showed: ")
    }
}
