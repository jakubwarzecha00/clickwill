import SwiftUI
import ClickwillModel

/// The popover with connected iPods, opened by the arrow on the iPod card.
/// No separate list in the sidebar: the iPod is
/// the starting point, not one of the navigation items.
struct IPodPicker: View {
    let choices: [IPodChoice]
    let currentID: String?
    let choose: (IPodChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connected iPods")
                .font(.theme(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            ForEach(choices) { choice in
                IPodPickerRow(choice: choice, isCurrent: choice.id == currentID) { choose(choice) }
            }
        }
        .padding(8)
        .frame(width: 320)
    }
}

private struct IPodPickerRow: View {
    let choice: IPodChoice
    let isCurrent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                // The model drawing in the color from the catalog.
                IPodGraphic(choice: choice)
                    .frame(width: 40, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.name).font(.theme(.row, weight: .semibold))
                    Text(choice.modelName)
                        .font(.theme(.caption)).foregroundStyle(.secondary)
                    Text("\(choice.totalCapacity.gigabytes) · \(choice.availableCapacity.gigabytes) free")
                        .font(.theme(.caption)).foregroundStyle(.secondary).monospacedDigit()
                    if choice.isReadOnly {
                        Label("Read-only", systemImage: "lock.fill")
                            .font(.theme(.small))
                            .foregroundStyle(Theme.warn)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.theme(.callout, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(8)
            .contentShape(.rect(cornerRadius: 8))
            .background(hovered ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(choice.isReadOnly ? ErrorPresenter.readOnlyMessage(choice.readOnlyReason) : "")
        .accessibilityLabel("\(choice.name), \(choice.modelName)\(isCurrent ? ", current" : "")")
    }
}
