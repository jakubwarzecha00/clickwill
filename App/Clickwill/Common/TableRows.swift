import Foundation
import Observation

/// What a long table shows, worked out only when the library, the search or the sort order
/// changes and not on every redraw. Searching and sorting 15,000 rows takes a noticeable moment,
/// so they run away from the main thread: the table keeps its rows until the new ones are ready.
@MainActor
@Observable
final class TableRows<Row: Sendable> {

    /// Everything the rows depend on. The screen passes it to `.onChange`.
    struct Request: Equatable {
        /// `LibraryModel.catalogRevision`
        let revision: Int
        let query: String
        let sortOrder: [KeyPathComparator<Row>]
    }

    private(set) var shown: [Row] = []
    /// Grows when a search or a sort rearranges the list; the screen gives it to the table as `.id`.
    /// A table that stays moves its rows one by one, and AppKit makes a view for every moved or
    /// inserted row to measure it: tens of seconds at 40,000 rows. A new table makes only the visible ones.
    private(set) var arrangement = 0
    /// Every row of the library, before searching and sorting.
    @ObservationIgnored private var all: [Row] = []
    @ObservationIgnored private var builtRevision: Int?
    @ObservationIgnored private var last: Request?
    /// The list was rearranged and that has not reached the table yet.
    @ObservationIgnored private var rearranged = false
    /// The newest search or sort. A newer one replaces it, and its result no longer counts.
    @ObservationIgnored private var work: Task<Void, Never>?

    func update(for request: Request, build: () -> [Row], matches: @escaping @Sendable (Row, String) -> Bool) {
        // The first fill happens right here: a table opened empty would flash before filling up.
        let first = builtRevision == nil
        if request.revision != builtRevision {
            all = build()
            builtRevision = request.revision
        }
        if let last, last.query != request.query || last.sortOrder != request.sortOrder { rearranged = true }
        last = request
        work?.cancel()
        let text = request.query.trimmingCharacters(in: .whitespaces)
        if first || (text.isEmpty && request.sortOrder.isEmpty) {
            show(Self.arranged(all, text: text, matches: matches, sortOrder: request.sortOrder))
            return
        }
        let rows = all
        work = Task {
            let arranged = await Task.detached(priority: .userInitiated) {
                Self.arranged(rows, text: text, matches: matches, sortOrder: request.sortOrder)
            }.value
            if !Task.isCancelled { show(arranged) }
        }
    }

    private func show(_ rows: [Row]) {
        if rearranged { arrangement += 1 }
        rearranged = false
        shown = rows
    }

    private nonisolated static func arranged(_ rows: [Row], text: String, matches: (Row, String) -> Bool,
                                             sortOrder: [KeyPathComparator<Row>]) -> [Row] {
        let found = text.isEmpty ? rows : rows.filter { matches($0, text) }
        return sortOrder.isEmpty ? found : found.sorted(using: sortOrder)
    }
}
