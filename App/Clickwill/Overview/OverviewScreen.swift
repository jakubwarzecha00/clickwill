import SwiftUI
import ClickwillModel

/// Overview: the device identity and the database state. A native `Form` in the
/// grouped style, like System Settings.
struct OverviewScreen: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        Form {
            ForEach(OverviewFacts.sections(of: model)) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.label) { label, value in
                        LabeledContent(label) {
                            Text(value).monospacedDigit().textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            DiagnosticsCard()
        }
        .formStyle(.grouped)
        // The window's scene background, as under Cover Flow and the lists - the Form's own gray background
        // ended above the playback bar with a darker strip.
        .scrollContentBackground(.hidden)
    }
}
