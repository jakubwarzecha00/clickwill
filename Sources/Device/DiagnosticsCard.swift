import SwiftUI
import ClickwillModel

/// A section in Overview: the two ways to reach me. The app shows the diagnostic report in full
/// before it is sent, so the tester sees what they send.
struct DiagnosticsCard: View {
    @Environment(\.deviceActions) private var actions

    var body: some View {
        Section {
            Text("Clickwill never sends a report on its own. Send Diagnostic Report checks this iPod and shows the whole report before you send it. Send Feedback is for a message, with the report if you choose. The report describes the iPod model and the state of its library, with no song titles, no names, and no serial numbers.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Send Diagnostic Report…") { actions.sendReport("") }
                Button("Send Feedback…") { actions.sendFeedback() }
                Spacer()
            }
        } header: {
            Text("Report a Problem")
        }
    }
}
