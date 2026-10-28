import SwiftUI
import AppKit
import ClickwillModel

/// A report from a tester, sent straight to the Clickwill server with the Send button
/// - without Mail and without the user's e-mail. Only the
/// text, the report if it was checked (it is visible before sending), and the version are sent.
///
/// An album can be chosen from the list - only then do its title and artwork details
/// go into the report. Without it the report describes the library in numbers.
struct FeedbackSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.siteURL) private var siteURL
    @State private var message = ""
    @State private var album = ""
    @State private var includeReport = false
    @State private var showReport = false
    @State private var sending = false
    @State private var sent = false
    @State private var failure: FeedbackSubmission.Failure?
    @FocusState private var editorFocused: Bool

    var body: some View {
        // A native macOS 27 sheet, like Add Songs and Pending Changes:
        // the title in the bar, a grouped Form, Cancel and Send in their standard places.
        NavigationStack {
            Form {
                Section {
                    Text("Tell me what happened, what you expected, or what you'd like Clickwill to do. I read every message myself.")
                        .foregroundStyle(.secondary)
                    TextField("Message", text: $message,
                              prompt: Text("What happened? For example: I changed the cover of an album, wrote to the iPod, and the iPod still shows the old one."),
                              axis: .vertical)
                        .labelsHidden()
                        // A frame as in the album inspector fields: it shows that this is where you type.
                        .multilineFieldStyle()
                        .lineLimit(7, reservesSpace: true)
                        .focused($editorFocused)
                        .disabled(sending || sent)
                }
                Section {
                    if !albumTitles.isEmpty {
                        Picker("Is it about one album?", selection: $album) {
                            Text("No, or several").tag("")
                            Divider()
                            ForEach(albumTitles, id: \.self) { Text($0).tag($0) }
                        }
                        .disabled(sending || sent)
                    }
                    Toggle("Include a diagnostic report", isOn: $includeReport)
                        .disabled(sending || sent)
                    // A button instead of a DisclosureGroup: that one did not expand in a Form
                    // when clicked (checked by clicking with the mouse).
                    if includeReport {
                        Button(showReport ? "Hide What's Included" : "Show What's Included") { showReport.toggle() }
                            .buttonStyle(.link)
                            .foregroundStyle(Color.accentColor)  // the window imposes Theme.fg, a link has the accent color
                        if showReport {
                            Text(report)
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } footer: {
                    Text(sent
                         ? "Thanks, your message should reach me soon."
                         : "Send delivers your message\(includeReport ? " and the diagnostic report" : "") to me at clickwilldev.com, with the version of Clickwill. Nothing else leaves your Mac, and no email address is needed.")
                    .foregroundStyle(.secondary)
                }
                if let failure {
                    Section {
                        Label(ErrorPresenter.message(for: failure), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Send Feedback")
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
        .frame(minWidth: 560, idealWidth: 600, minHeight: 440, idealHeight: 460)
        .sheetKeyFocus()
        .onAppear { editorFocused = true }
    }

    private var albumTitles: [String] {
        Array(Set((model.library?.tracks ?? []).compactMap(\.album).filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var report: String {
        DiagnosticsClipboard.report(model, album: album.isEmpty ? nil : album)
    }

    private var submission: FeedbackSubmission {
        FeedbackSubmission(message: message, report: includeReport ? report : nil,
                           version: AboutFacts.shortVersion, build: AboutFacts.build)
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

private extension View {
    /// On macOS 14-25 the `.roundedBorder` style draws a single-line system field
    /// and ignores `axis: .vertical` and the line reserve - the message had one
    /// line (checked on macOS 14). There, a `.plain` field with its own frame and field background.
    @ViewBuilder func multilineFieldStyle() -> some View {
        if #available(macOS 26, *) {
            textFieldStyle(.roundedBorder)
        } else {
            textFieldStyle(.plain)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }
}
