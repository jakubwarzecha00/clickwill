import SwiftUI
import ClickwillModel
import ClickwillShared

/// A Videos page. Read only for now.
public struct VideosScreen: View {
    let page: VideosPage

    public init(page: VideosPage) {
        self.page = page
    }

    public var body: some View {
        switch page {
        case .movies: MoviesScreen()
        case .tvShows: TVShowsScreen()
        }
    }
}

/// TV shows are not measured yet, so the page can only say whether anything is left unsorted.
struct TVShowsScreen: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        EmptyStateView.unsortedMedia(none: "No TV Shows on This iPod", unrecognized: model.videos.unrecognizedCount)
    }
}

/// The movies already on the iPod in one sortable, searchable table.
struct MoviesScreen: View {
    @Environment(LibraryModel.self) private var model
    /// Empty means the database order.
    @State private var sortOrder: [KeyPathComparator<Row>] = []
    @State private var query = ""
    @State private var selection = Set<UInt32>()
    @State private var rows = TableRows<Row>()
    /// Kept outside the table: a search or a sort replaces the table (`TableRows.arrangement`).
    @State private var columns = TableColumnCustomization<Row>()

    struct Row: Identifiable, Sendable {
        let id: UInt32; let title: String; let duration: TimeInterval; let size: Int64; let added: Date
    }

    private func allRows() -> [Row] {
        model.videos.movies.map {
            Row(id: $0.id, title: $0.displayTitle, duration: $0.duration, size: $0.sizeBytes,
                added: $0.dateAdded ?? .distantPast)
        }
    }

    var body: some View {
        let request = TableRows<Row>.Request(revision: model.catalogRevision, query: query, sortOrder: sortOrder)
        Group {
            if model.videos.movies.isEmpty {
                EmptyStateView(text: "No Movies on This iPod",
                               detail: "Movies you put on it with Finder or Apple TV will show up here.")
            } else {
                table(rows.shown)
            }
        }
        .onChange(of: request, initial: true) {
            rows.update(for: request, build: allRows) { row, text in row.title.localizedStandardContains(text) }
        }
    }

    private func table(_ shown: [Row]) -> some View {
        Table(shown, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            TableColumn("Title", value: \.title).customizationID("title").disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Time", value: \.duration) { Text($0.duration.clockLabel).monospacedDigit() }.width(70)
                .customizationID("time").disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Size", value: \.size) { Text($0.size.formatted(.byteCount(style: .file))).monospacedDigit() }.width(80)
                .customizationID("size").disabledCustomizationBehavior([.reorder, .visibility])
            TableColumn("Date Added", value: \.added) { row in
                Text(row.added == .distantPast ? "" : row.added.formatted(date: .abbreviated, time: .omitted))
            }
            .width(110)
            .customizationID("added").disabledCustomizationBehavior([.reorder, .visibility])
        }
        .id(rows.arrangement)
        .accessibilityIdentifier("movies.table")
        .searchable(text: $query, placement: .toolbar, prompt: "Search Movies")
        .scrollContentBackground(.hidden)
        .background(Theme.stage)
    }
}
