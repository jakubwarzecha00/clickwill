import SwiftUI
import ClickwillModel

/// All tracks in one table: sorting by column, searching,
/// playing with a double click.
struct SongsScreen: View {
    @Environment(LibraryModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    /// Opens the song's album ("Show Album").
    var openAlbum: (AlbumCard) -> Void = { _ in }
    /// An empty list = the library order (by album), as before.
    @State private var sortOrder: [KeyPathComparator<Row>] = []
    @State private var query = ""
    @State private var selection = Set<UInt32>()
    /// Editing from the table - this is where a song is easiest to find. Return plays, as in Music, so the title and number
    /// are changed in a small window from the menu, not in a table cell.
    @State private var editing: Row?
    @State private var error: String?
    /// Duplicates to review - collected at the moment of the click, not on every redraw of the sheet.
    @State private var duplicates: [DuplicateGroup]?

    struct Row: Identifiable {
        let id: UInt32; let title: String; let artist: String; let album: String; let duration: TimeInterval; let plays: UInt32
        let track: TrackRow; let card: AlbumCard
    }
    private var rows: [Row] {
        let all = model.albums.flatMap { album in
            model.tracks(of: album).map { Row(id: $0.id, title: $0.displayTitle, artist: $0.artist, album: album.displayTitle,
                                              duration: $0.duration, plays: $0.playCount, track: $0, card: album) }
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        let found = text.isEmpty ? all : all.filter {
            $0.title.localizedStandardContains(text) || $0.artist.localizedStandardContains(text) || $0.album.localizedStandardContains(text)
        }
        return sortOrder.isEmpty ? found : found.sorted(using: sortOrder)
    }

    var body: some View {
        let shown = rows
        VStack(spacing: 0) {
            duplicatesBar
            table(shown)
        }
        .sheet(isPresented: Binding(get: { duplicates != nil }, set: { if !$0 { duplicates = nil } })) {
            DuplicatesSheet(groups: duplicates ?? []).environment(model)
        }
    }

    /// The bar above the table only when there are duplicates on the iPod.
    @ViewBuilder private var duplicatesBar: some View {
        // In --demo also on a backup from Backups (a website video): writing is blocked anyway.
        let groups = model.isWritable || model.writesBlocked ? model.duplicateGroups() : []
        if !groups.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "square.on.square").foregroundStyle(Theme.accent)
                Text(groups.count == 1 ? "1 song is on your iPod more than once."
                                       : "\(groups.count) songs are on your iPod more than once.")
                    .font(.theme(.body))
                Spacer()
                Button("Review Duplicates…") { duplicates = model.duplicateGroups() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.card)
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func table(_ shown: [Row]) -> some View {
        Table(shown, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
            TableColumn("Plays", value: \.plays) { Text("\($0.plays)").monospacedDigit() }.width(60)
            TableColumn("Time", value: \.duration) { Text($0.duration.clockLabel).monospacedDigit() }.width(60)
        }
        .contextMenu(forSelectionType: UInt32.self) { ids in
            menu(for: ids, in: shown)
        } primaryAction: { ids in
            play(ids.first, in: shown)
        }
        .onDeleteCommand { delete(selection, in: shown) }
        .searchable(text: $query, placement: .toolbar, prompt: "Search Songs")
        .scrollContentBackground(.hidden)
        .background(Theme.stage)
        .sheet(item: $editing) { row in
            SongInfoSheet(row: row) { title, number in
                model.renameTrack(row.track, in: row.card, to: title)
                model.setTrackNumber(row.track, in: row.card, to: number)
            }
        }
        .alert("This change couldn't be made", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private func menu(for ids: Set<UInt32>, in shown: [Row]) -> some View {
        let single = ids.count == 1 ? shown.first { $0.id == ids.first } : nil
        Button("Play") { play(ids.first, in: shown) }.disabled(ids.isEmpty)
        Divider()
        Button("Edit Title…") { editing = single }.disabled(single == nil)
        Button("Show Album") { if let single { openAlbum(single.card) } }.disabled(single == nil)
        Divider()
        Button(ids.count > 1 ? "Delete \(ids.count) Songs from iPod" : "Delete from iPod", role: .destructive) {
            delete(ids, in: shown)
        }
        .disabled(ids.isEmpty)
    }

    /// Deleting is a change in the queue, as in the album view - "Discard All" undoes it.
    private func delete(_ ids: Set<UInt32>, in shown: [Row]) {
        do {
            for row in shown where ids.contains(row.id) { try model.deleteTrack(row.track, in: row.card) }
            selection.subtract(ids)
        } catch {
            self.error = ErrorPresenter.message(for: error)
        }
    }

    /// Plays a track from the iPod, and after it the rest of its album - as in the album view.
    private func play(_ id: UInt32?, in shown: [Row]) {
        guard let id, let row = shown.first(where: { $0.id == id }) else { return }
        playback.play(model.tracks(of: row.card), startingAt: row.track, in: row.card)
    }
}

/// A song's title and number from the Songs table. The change goes to the queue like any other.
struct SongInfoSheet: View {
    let row: SongsScreen.Row
    let save: (String, UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var number = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline).lineLimit(1)
                Text("\(row.artist) · \(row.album)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Form {
                TextField("Title", text: $title)
                TextField("Track number", text: $number)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(title, UInt32(number.filter(\.isNumber)) ?? 0)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            title = row.track.title
            number = row.track.number > 0 ? "\(row.track.number)" : ""
        }
    }
}
