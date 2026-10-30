import SwiftUI
import AppKit
import ClickwillModel
import ITDBKit

/// Send Diagnostic Report, over Diagnostics: the whole report visible before sending, an
/// optional comment, Send. The same text as Copy Report and as the report in Send Feedback
/// (`DiagnosticReport`). Technical wording, without the first person.
struct SendReportSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.siteURL) private var siteURL
    /// What the user saw in Diagnostics; `nil` without an iPod.
    let diagnostics: Diagnostics?
    @State private var comment: String
    @State private var sending = false
    @State private var sent = false
    @State private var copied = false
    @State private var failure: FeedbackSubmission.Failure?

    init(diagnostics: Diagnostics?, comment: String) {
        self.diagnostics = diagnostics
        _comment = State(initialValue: comment)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Comment", text: $comment,
                              prompt: Text("Optional. What happened, what the iPod showed, what was expected."),
                              axis: .vertical)
                        .labelsHidden()
                        .multilineFieldStyle()
                        .lineLimit(3, reservesSpace: true)
                        .disabled(sending || sent)
                } header: {
                    Text("Comment")
                }
                Section {
                    Text(report)
                        .font(.theme(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } header: {
                    HStack {
                        Text("Report")
                        Spacer()
                        Button(copied ? "Copied" : "Copy Report") { copy() }
                            .buttonStyle(.link)
                            .foregroundStyle(Color.accentColor)  // the window imposes Theme.fg, a link has the accent color
                    }
                } footer: {
                    Text(sent
                         ? "Sent."
                         : "Sent to clickwilldev.com with the Clickwill version. No GUID, serial number, iPod name, song titles or folder names.")
                        .foregroundStyle(.secondary)
                }
                if let failure {
                    Section {
                        Label(ErrorPresenter.message(for: failure), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.warn)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Send Diagnostic Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(sending ? "Sending…" : "Send") { send() }
                            .disabled(sending || !submission.canSend)
                    }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 680, minHeight: 520, idealHeight: 640)
        .sheetKeyFocus()
    }

    private var report: String { DiagnosticsClipboard.report(model, diagnostics: diagnostics) }

    /// The first line says what the report is about even when the comment stays empty.
    private var message: String {
        let subject = "Diagnostic report · \(model.device?.model.name ?? "no iPod") · \(diagnostics?.verdict ?? "no diagnostics")"
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? subject : "\(subject)\n\n\(text)"
    }

    private var submission: FeedbackSubmission {
        FeedbackSubmission(message: message, report: report, version: AboutFacts.shortVersion, build: AboutFacts.build)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copied = true
    }

    private func send() {
        let submission = submission
        sending = true
        failure = nil
        Task {
            let failure = await submission.send(to: siteURL)
            sending = false
            if let failure { self.failure = failure } else { sent = true }
        }
    }
}
