import SwiftUI
import ClickwillShared

/// How much space on the right the panel slid out by the current screen takes.
/// The playback bar stands above all screens and would otherwise have no way to
/// know that it should narrow.
struct SidePanelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The bar at the bottom of the window: playback, then the modules' items (the write state and
/// the pending changes button).
struct StatusBarView: View {
    /// A panel slid out on the right takes as much of the bar as it takes itself.
    var trailingReserve: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            PlaybackBarControls()
            ModuleStatusItems()
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.playerBarHeight - 14)
        .liquidPanel()
        .frame(maxWidth: Theme.playerBarWidth)
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 0, leading: 14, bottom: 30, trailing: 14))
        .padding(.trailing, trailingReserve)
        .animation(.easeOut(duration: 0.22), value: trailingReserve)
    }
}
