import SwiftUI
import ClickwillModel

/// How much space on the right the panel slid out by the current screen takes.
/// The playback bar stands above all screens and would otherwise have no way to
/// know that it should narrow.
struct SidePanelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The bar at the bottom of the window: playback, the write block and the number of changes waiting
/// to be written (it opens their list).
struct StatusBarView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window
    /// A panel slid out on the right takes as much of the bar as it takes itself.
    var trailingReserve: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            PlaybackBarControls()
            if let preflight = model.preflight(), !preflight.isClear {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warn)
                    .help(preflight.blocking.first.map(ErrorPresenter.message(for:)) ?? "")
                    .accessibilityLabel(preflight.blocking.first.map(ErrorPresenter.message(for:)) ?? "Write unavailable")
            } else if !model.isWritable, model.state == .loaded {
                Image(systemName: "lock").foregroundStyle(Theme.f2)
                    .help(model.writeUnavailable.map(ErrorPresenter.message(for:)) ?? "Read-only")
                    .accessibilityLabel("Read-only")
            }
            if model.hasPendingChanges {
                Button { window.showPending() } label: {
                    HStack(spacing: 8) {
                        // An accent dot on the glass; on 14-25 the whole button is in the accent color.
                        if #available(macOS 26, *) { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
                        Text("\(model.changes.log.count) change\(model.changes.log.count == 1 ? "" : "s") pending")
                            .font(.theme(.body, weight: .medium))
                        Image(systemName: "chevron.right").font(.symbol(.small, weight: .bold)).foregroundStyle(Theme.f2)
                    }
                    .liquidChip(selected: true, height: 30, padding: 12)
                }.chipButton(selected: true)
            } else {
                Text("No pending changes").font(.theme(.callout)).foregroundStyle(Theme.f3)
            }
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
