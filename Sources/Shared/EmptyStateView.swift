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

public extension EmptyStateView {
    /// A Media screen whose kind Clickwill cannot recognize yet (TV shows, podcasts). With no
    /// unrecognized records it can say for sure that there are none; otherwise it must not.
    static func unsortedMedia(none: String, unrecognized: Int) -> EmptyStateView {
        guard unrecognized > 0 else { return EmptyStateView(text: none) }
        let items = unrecognized == 1 ? "1 item that isn't a song or a movie" : "\(unrecognized) items that aren't songs or movies"
        return EmptyStateView(text: "Some Items Aren't Sorted Yet",
                              detail: "Your iPod has \(items). I can't tell yet what they are, so I leave them untouched.")
    }
}
