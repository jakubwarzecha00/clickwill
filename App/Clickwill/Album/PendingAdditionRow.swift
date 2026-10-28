import SwiftUI
import ClickwillModel

/// A track waiting to be added to an album: it is visible in the list already, but
/// it reaches the iPod only on "Write to iPod".
struct PendingAdditionRow: View {
    let addition: PendingAddition
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.theme(.callout, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(addition.draft.title).font(.theme(.row)).lineLimit(1)
                Text(detail).font(.theme(.caption)).foregroundStyle(Theme.f2).lineLimit(1)
            }
            Spacer()
            Button("Remove", action: remove)
                .buttonStyle(.plain)
                .font(.theme(.footnote, weight: .medium))
                .foregroundStyle(Theme.f2)
                .help("Don't add this song")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .opacity(0.75)
    }

    private var detail: String {
        var parts = ["Added on Write to iPod"]
        if let index = addition.placement?.index { parts.append("Goes in as song \(index + 1)") }
        if addition.needsConversion, let target = addition.target { parts.append("Converted to \(target.label)") }
        return parts.joined(separator: " · ")
    }
}
