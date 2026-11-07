import SwiftUI
import ClickwillModel

/// All artists in one table: sorting by column, searching,
/// opening artist's albums.
struct ArtistsScreen: View {
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window
    /// Opens the artist's album.
    var openAlbum: (AlbumCard) -> Void = { _ in }
    @State private var sortOrder: [KeyPathComparator<Row>] = [KeyPathComparator(\Row.artist, comparator: .localizedStandard)]
    @State private var query = ""
    @State private var selection = Set<String>()
    @State private var error: String?

    @State private var rows = TableRows<Row>()
    /// Column widths: kept here, because a search or a sort puts a new table in place (`TableRows.arrangement`).
    @State private var columns = TableColumnCustomization<Row>()

    struct Row: Identifiable, Sendable {
        let id: String
        let artist: String
        let albumCount: Int
        let songCount: Int
        let albums: [AlbumCard]
    }

    private func allRows() -> [Row] {
        let artistMap: [String: (albums: [AlbumCard], songs: Int)] = model.albums.reduce(into: [:]) { dict, album in
            let artist = album.displayArtist
            if dict[artist] == nil {
                dict[artist] = (albums: [], songs: 0)
            }
            dict[artist]?.albums.append(album)
            dict[artist]?.songs += album.trackCount
        }

        return artistMap.map { (artist, data) in
            Row(id: artist, artist: artist, albumCount: data.albums.count, songCount: data.songs, albums: data.albums)
        }
    }

    var body: some View {
        let request = TableRows<Row>.Request(revision: model.catalogRevision, query: query, sortOrder: sortOrder)
        Table(rows.shown, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("Artist", value: \.artist).customizationID("artist").disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Albums", value: \.albumCount) { Text("\($0.albumCount)").monospacedDigit() }.width(60)
                .customizationID("albums").disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Songs", value: \.songCount) { Text("\($0.songCount)").monospacedDigit() }.width(60)
                .customizationID("songs").disabledCustomizationBehavior([.reorder, .visibility])
        }
        .id(rows.arrangement)
        .onChange(of: request, initial: true) {
            rows.update(for: request, build: allRows) { row, text in row.artist.localizedStandardContains(text) }
        }
        .contextMenu(forSelectionType: String.self) { artists in
            menu(for: artists)
        } primaryAction: { artists in
            if let artist = artists.first {
                window.openArtist(artist)
            }
        }
        .onDeleteCommand {
            if !selection.isEmpty {
                delete(selection)
            }
        }
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
                delete(artist)
            }
        } else if !artists.isEmpty {
            Button("Delete \(artists.count) Artists from iPod", role: .destructive) {
                delete(artists)
            }
        }
    }

    private func delete(_ artist: String) {
        guard let row = rows.shown.first(where: { $0.id == artist }) else { return }
        let albums = row.albums
        let trackCount = row.songCount
        let fileCount = albums.reduce(0) { $0 + model.deletableFileCount(of: $1) }
        let albumTitle = albums.count == 1 ? albums[0].displayTitle : artist

        let choice = DeleteAlbumConfirmation.ask(
            album: albumTitle, artist: artist,
            trackCount: trackCount, fileCount: fileCount
        )

        let archive: URL?
        switch choice {
        case .cancelled: return
        case .delete: archive = nil
        case .deleteKeepingCopies(let url): archive = url
        }

        do {
            for album in albums {
                try model.deleteAlbum(album, keepCopiesIn: archive)
            }
            selection.remove(artist)
        } catch {
            self.error = ErrorPresenter.message(for: error)
        }
    }

    private func delete(_ artists: Set<String>) {
        for artist in artists {
            guard let row = rows.shown.first(where: { $0.id == artist }) else { continue }
            let albums = row.albums
            let trackCount = row.songCount
            let fileCount = albums.reduce(0) { $0 + model.deletableFileCount(of: $1) }
            let albumTitle = albums.count == 1 ? albums[0].displayTitle : artist

            let choice = DeleteAlbumConfirmation.ask(
                album: albumTitle, artist: artist,
                trackCount: trackCount, fileCount: fileCount
            )

            let archive: URL?
            switch choice {
            case .cancelled: continue
            case .delete: archive = nil
            case .deleteKeepingCopies(let url): archive = url
            }

            do {
                for album in albums {
                    try model.deleteAlbum(album, keepCopiesIn: archive)
                }
                selection.remove(artist)
            } catch {
                self.error = ErrorPresenter.message(for: error)
                return
            }
        }
    }
}
