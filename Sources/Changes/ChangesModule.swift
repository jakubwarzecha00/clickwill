import SwiftUI
import ClickwillModel
import ClickwillShared

/// The playback bar's write state: what blocks writing, and the pending changes button
/// that opens their list.
public struct ChangesStatusItems: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.changesActions) private var actions

    public init() {}

    public var body: some View {
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
            Button { actions.showChanges() } label: {
                HStack(spacing: 8) {
                    // An accent dot on the glass; on 14-25 the whole button is in the accent color.
                    if #available(macOS 26, *) { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
                    Text(Self.pendingTitle(model.changes.log.count))
                        .font(.theme(.body, weight: .medium))
                    Image(systemName: "chevron.right").font(.symbol(.small, weight: .bold)).foregroundStyle(Theme.f2)
                }
                .liquidChip(selected: true, height: 30, padding: 12)
            }.chipButton(selected: true)
        } else {
            Text("No pending changes").font(.theme(.callout)).foregroundStyle(Theme.f3)
        }
    }

    static func pendingTitle(_ count: Int) -> String {
        "\(count) change\(count == 1 ? "" : "s") pending"
    }
}

/// What the change list asks the window to do.
public struct ChangesActions: Sendable {
    public var showChanges: @MainActor @Sendable () -> Void

    public init(showChanges: @escaping @MainActor @Sendable () -> Void) {
        self.showChanges = showChanges
    }

    static let none = ChangesActions(showChanges: {})
}

public extension EnvironmentValues {
    @Entry var changesActions: ChangesActions = .none
}
