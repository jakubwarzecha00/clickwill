import SwiftUI

public struct EmptyStateView: View {
    let text: String
    var detail: String? = nil
    /// Loading must not look like a missing device - hence a spinner
    /// instead of an icon, and a sentence about not pulling the cable.
    var busy = false

    public init(text: String, detail: String? = nil, busy: Bool = false) {
        self.text = text
        self.detail = detail
        self.busy = busy
    }

    public var body: some View {
        // The system empty state. Colors explicitly: the window imposes Theme.fg.
        ContentUnavailableView {
            if busy {
                ProgressView().controlSize(.large)
                Text(text)
            } else {
                Label(text, systemImage: "ipod")
            }
        } description: {
            if let detail { Text(detail).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.stage)
    }
}
