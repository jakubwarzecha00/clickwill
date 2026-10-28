import SwiftUI
import ClickwillModel

/// A section in Overview. It shows the content before copying - the tester sees what they send.
struct DiagnosticsCard: View {
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window
    @State private var copied = false
    @State private var showText = false

    var body: some View {
        Section {
            Text("Clickwill never sends a report on its own. To report a problem, use Send Feedback: your message comes straight to me, and you choose whether the diagnostic report goes along. The report describes the iPod model and the state of its library, with no song titles, no names, and no serial numbers.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Send Feedback…") { window.showFeedback() }
                Button(copied ? "Copied" : "Copy Diagnostic Report") {
                    DiagnosticsClipboard.copy(model)
                    copied = true
                }
                Spacer()
                // A button instead of a DisclosureGroup: that one did not expand in a Form
                // when clicked (checked by clicking with the mouse).
                Button(showText ? "Hide Report" : "Show Report") { showText.toggle() }
                    .buttonStyle(.link)
                    .foregroundStyle(Color.accentColor)  // the window imposes Theme.fg, a link has the accent color
            }
            if showText {
                Text(DiagnosticsClipboard.report(model))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Report a Problem")
        }
        .onChange(of: model.generation) { copied = false }
    }
}
