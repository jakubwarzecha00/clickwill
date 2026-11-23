import SwiftUI

/// An inspector field: it looks like the former read-only field, but
/// accepts text. Committed with Return or by losing focus, Escape reverts.
/// A field in the inspector Form: the label on the left, the value on the right, as in the system.
/// Committed with Return or by losing focus; Escape reverts.
struct InspectorTextField: View {
    let label: String
    let value: String
    var placeholder: String = ""
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        // A field frame as in Apple's inspectors (Xcode, Pages): without it the grouped Form
        // drew the field like a plain value, and it was not visible that it can be changed.
        LabeledContent(label) {
            TextField(label, text: $draft, prompt: Text(placeholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 170)
                .monospacedDigit()
                .focused($focused)
            .onSubmit { focused = false }
            .onExitCommand { draft = value; focused = false }
            .onChange(of: focused) { _, isFocused in if !isFocused, draft != value { commit(draft) } }
            .onChange(of: value) { _, new in if !focused { draft = new } }
                .onAppear { draft = value }
        }
    }
}
