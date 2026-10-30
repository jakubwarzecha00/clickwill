import SwiftUI
import ClickwillModel

/// All artists in one table: sorting by column, searching,
/// opening artist's albums.
struct ArtistsScreen: View {
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window
    /// Opens the artist's album.
    var openAlbum: (AlbumCard) -> Void = { _ in }
    @State private var sortOrder: [KeyPathComparator<Row>] = []
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var error: String?

    struct Row: Identifiable {
        let id: String
        let artist: String
        let albumCount: Int
        let songCount: Int
        let albums: [AlbumCard]
    }

    private var rows: [Row] {
        let artistMap: [String: (albums: [AlbumCard], songs: Int)] = model.albums.reduce(into: [:]) { dict, album in
            let artist = album.displayArtist
            if dict[artist] == nil {
                dict[artist] = (albums: [], songs: 0)
            }
            dict[artist]?.albums.append(album)
            dict[artist]?.songs += model.tracks(of: album).count
        }

        let all = artistMap.map { (artist, data) in
            Row(id: artist, artist: artist, albumCount: data.albums.count, songCount: data.songs, albums: data.albums)
        }

        let text = query.trimmingCharacters(in: .whitespaces)
        let found = text.isEmpty ? all : all.filter { $0.artist.localizedStandardContains(text) }
        return sortOrder.isEmpty ? found : found.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Artist", value: \.artist)
            TableColumn("Albums", value: \.albumCount) { Text("\($0.albumCount)").monospacedDigit() }.width(60)
            TableColumn("Songs", value: \.songCount) { Text("\($0.songCount)").monospacedDigit() }.width(60)
        }
        .contextMenu(forSelectionType: String.self) { artists in
            menu(for: artists)
        } primaryAction: { artists in
            if let artist = artists.first {
                window.openArtist(artist)
            }
        }
        .onDeleteCommand { delete(selection) }
        .searchable(text: $query, placement: .toolbar, prompt: "Search Artists")
        .scrollContentBackground(.hidden)
        .background(Theme.stage)
        .alert("This change couldn't be made", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private func menu(for artists: Set<String>) -> some View {
        if artists.count == 1, let artist = artists.first {
            Button("Show Albums") { window.openArtist(artist) }
            Divider()
            Button("Delete Artist from iPod", role: .destructive) {
                delete(artists)
            }
            .disabled(rows.contains { artists.contains($0.id) && $0.albums.allSatisfy { model.isSyncedOnDevice(model.tracks(of: $0).first!) } })
        } else if !artists.isEmpty {
            Button("Delete \(artists.count) Artists from iPod", role: .destructive) {
                delete(artists)
            }
        }
    }

    private func delete(_ artists: Set<String>) {
        do {
            for row in rows where artists.contains(row.id) {
                for album in row.albums {
                    for track in model.tracks(of: album) {
                        try model.deleteTrack(track, in: album)
                    }
                }
            }
            selection.subtract(artists)
        } catch {
            self.error = ErrorPresenter.message(for: error)
        }
    }
}
