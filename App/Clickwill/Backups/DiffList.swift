import SwiftUI
import ITDBKit
import ClickwillModel

/// Changes between two libraries, expandable by album.
///
/// The same view serves both questions on the backups screen: what the write changed
/// (the forward direction) and what the restore will undo (from now to the backup) - they differ
/// only in words, because "added" means something different in each.
struct DiffList: View {
    enum Direction { case forward, restore }

    let diff: LibraryDiff
    let direction: Direction

    var body: some View {
        let albums = diff.albums
        Group {
            if diff.albumOrderChanged {
                Label(direction == .forward ? "Album order in the iPod\u{2019}s menus changed"
                                            : "Album order in the iPod\u{2019}s menus would go back",
                      systemImage: "arrow.up.arrow.down")
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(albums) { album in
                AlbumDiffRow(album: album, direction: direction,
                             startsExpanded: albums.count <= 3)
            }
        }
    }
}

private struct AlbumDiffRow: View {
    let album: LibraryDiff.AlbumChanges
    let direction: DiffList.Direction
    @State private var expanded: Bool

    init(album: LibraryDiff.AlbumChanges, direction: DiffList.Direction, startsExpanded: Bool) {
        self.album = album
        self.direction = direction
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(album.added, id: \.persistentID) { song in
                    line(direction == .forward ? "plus.circle" : "arrow.uturn.backward.circle",
                         Color.green, direction == .forward ? "Added" : "Comes back", song.title)
                }
                ForEach(album.removed, id: \.persistentID) { song in
                    line("minus.circle", Color.orange,
                         direction == .forward ? "Removed" : "Leaves the menus, file stays", song.title)
                }
                ForEach(album.edits, id: \.self) { edit in
                    editLine(edit)
                }
            }
            .padding(.leading, 4).padding(.top, 5)
        } label: {
            HStack(spacing: 6) {
                Text(album.album.isEmpty ? "Unknown album" : album.album)
                    .font(.theme(.body, weight: .semibold)).lineLimit(1)
                if !album.artist.isEmpty {
                    Text(album.artist).font(.theme(.callout)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(album.changeCount == 1 ? "1 change" : "\(album.changeCount) changes")
                    .font(.theme(.caption)).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
    }

    private func line(_ icon: String, _ tint: Color, _ verb: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).font(.theme(.small)).foregroundStyle(tint).frame(width: 14)
            Text(verb).font(.theme(.footnote)).foregroundStyle(.secondary)
            Text(title).font(.theme(.callout)).lineLimit(1)
        }
    }

    private func editLine(_ edit: LibraryDiff.GroupedEdit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "pencil").font(.theme(.small)).foregroundStyle(Color.accentColor).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if let sentence = Self.coverSentence(edit) {
                        Text(sentence)
                    } else {
                        let label = Text(edit.field.rawValue + ": ").foregroundStyle(.secondary)
                        let before = Text(Self.shown(edit.before, field: edit.field)).foregroundStyle(.secondary)
                        let arrow = Text("  \u{2192}  ").foregroundStyle(.tertiary)
                        let after = Text(Self.shown(edit.after, field: edit.field))
                        Text("\(label)\(before)\(arrow)\(after)")
                    }
                }
                .font(.theme(.callout)).fixedSize(horizontal: false, vertical: true)
                Text(Self.songs(edit.songs)).font(.theme(.caption)).foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .help(edit.songs.map(\.title).joined(separator: "\n"))
            }
        }
    }

    /// The value to show. Artwork is an internal image identifier -
    /// for a human all that matters is whether it is there or not.
    static func shown(_ value: String, field: LibraryDiff.Field) -> String {
        if value.isEmpty { return field == .cover ? "none" : "\u{2014}" }
        if field == .cover { return "set" }
        return "\u{201C}\(value)\u{201D}"
    }

    /// Artwork has no value worth showing - only an event.
    static func coverSentence(_ edit: LibraryDiff.GroupedEdit) -> String? {
        guard edit.field == .cover else { return nil }
        switch (edit.before.isEmpty, edit.after.isEmpty) {
        case (true, false): return "Cover added"
        case (false, true): return "Cover removed"
        default: return "Cover replaced"
        }
    }

    static func songs(_ songs: [LibraryDiff.Song]) -> String {
        switch songs.count {
        case 1: return songs[0].title
        case 2...4: return songs.map(\.title).joined(separator: ", ")
        default: return "\(songs.count) songs, hover to list them"
        }
    }
}
