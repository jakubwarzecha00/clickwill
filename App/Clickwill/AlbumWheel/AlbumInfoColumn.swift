import SwiftUI
import ClickwillModel

/// A quiet column next to the Albums wheel: what is going on with the selected album on the iPod.
/// Problems only when there are any - with a healthy album the column is three
/// lines of data. "Convert…" opens the album, because that is where conversion is.
struct AlbumInfoColumn: View {
    @Environment(LibraryModel.self) private var model
    let album: AlbumCard
    let open: (AlbumCard) -> Void

    static let width: CGFloat = 270

    var body: some View {
        let facts = model.facts(of: album)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text([album.year.map(String.init), album.genre].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                Text("\(album.trackCount) song\(album.trackCount == 1 ? "" : "s") · \(album.duration.minutesLabel)")
            }
            .font(.theme(.row)).foregroundStyle(Theme.f2).monospacedDigit()
            VStack(alignment: .leading, spacing: 4) {
                Text(album.isPending ? "To Be Added" : "On the iPod")
                    .font(.theme(.small, weight: .semibold)).textCase(.uppercase).tracking(0.7)
                    .foregroundStyle(Color(white: 0.92).opacity(0.55))
                Text("\(facts.format ?? "Mixed formats") · \(facts.bytes.formatted(.byteCount(style: .file)))")
                    .font(.theme(.row)).foregroundStyle(Theme.f2).monospacedDigit()
            }
            ForEach(issues(facts), id: \.text) { issue in
                VStack(alignment: .leading, spacing: 6) {
                    Label(issue.text, systemImage: issue.symbol)
                        .font(.theme(.body)).foregroundStyle(issue.pending ? Theme.accent : Theme.warn)
                    if let note = issue.note {
                        Text(note).font(.theme(.footnote)).foregroundStyle(Theme.f3).padding(.leading, 24)
                    }
                    if let action = issue.action {
                        Button(action) { open(album) }
                            .font(.theme(.callout, weight: .medium))
                            .chipButton(selected: false, small: true)
                            .liquidChip(height: 24, padding: 11)
                            .help("Opens the album, where you finish this.")
                            .padding(.leading, 24)
                    }
                }
            }
        }
        .lineLimit(1)
        .frame(width: Self.width, alignment: .leading)
    }

    private struct Issue {
        let text: String
        let symbol: String
        var note: String? = nil
        var action: String? = nil
        var pending = false
    }

    private func issues(_ facts: AlbumFacts) -> [Issue] {
        var issues: [Issue] = []
        if album.isPending {
            issues.append(Issue(text: "Added on Write to iPod", symbol: "clock",
                                note: facts.convertsTo.map { "Saved as \($0)" }, pending: true))
        }
        if facts.unplayable > 0 {
            issues.append(Issue(text: "\(facts.unplayable) song\(facts.unplayable == 1 ? " skips" : "s skip") on the iPod",
                                symbol: "exclamationmark.triangle.fill", action: "Convert…"))
        }
        if album.missingFiles > 0 {
            issues.append(Issue(text: "\(album.missingFiles) entr\(album.missingFiles == 1 ? "y" : "ies") without a file",
                                symbol: "exclamationmark.circle.fill",
                                note: album.missingFiles == 1 ? "It skips on the iPod." : "They skip on the iPod."))
        }
        if !album.hasArtwork {
            issues.append(Issue(text: "No cover", symbol: "photo"))
        }
        return issues
    }
}
