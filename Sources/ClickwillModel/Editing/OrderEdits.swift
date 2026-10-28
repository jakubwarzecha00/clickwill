import Foundation
import ITDBKit

/// Order: tracks within an album and albums within a Cover Flow group. Both go through
/// the browse tables, as on the iPod.
extension LibraryEditor {

    /// Moves tracks within an album - semantics like `Array.move(fromOffsets:toOffset:)`.
    mutating func moveTracks(in album: AlbumCard, fromOffsets: IndexSet, toOffset: Int) throws {
        // A card without a counterpart in the album table (a group assembled from parts of
        // blocks) has no single block that could be permuted.
        guard let album = catalog.block(for: album) else { throw AlbumOrderError.albumNotFound(album.title) }
        try catalog.requireSingleBlock(album)
        var order = records(of: album)
        let movedTitles = fromOffsets.map { Self.displayTitle(order[$0]) }
        let before = order.map(\.uniqueID)
        order.moving(fromOffsets: fromOffsets, toOffset: toOffset)
        let after = order.map(\.uniqueID)
        guard before != after else { return }
        library = try library.settingTrackOrder(album: album.title, uniqueIDs: after)
        for (title, id) in zip(movedTitles, fromOffsets.map { before[$0] }) {
            let from = before.firstIndex(of: id) ?? 0
            let to = after.firstIndex(of: id) ?? 0
            recordChange(.trackMoved(album: album.title, track: title, from: from, to: to))
        }
    }

    /// Moves an album within its Cover Flow group. Within a group the order
    /// comes from the album table, so this is a plain block move before/after a neighbor.
    mutating func moveAlbumWithinGroup(_ album: AlbumCard, in group: CoverFlowGroup, toOffset: Int) throws {
        guard let from = group.albums.firstIndex(where: { $0.id == album.id }) else { return }
        var order = group.albums
        order.moving(fromOffsets: IndexSet(integer: from), toOffset: toOffset)
        guard let to = order.firstIndex(where: { $0.id == album.id }), to != from else { return }
        try catalog.requireSingleBlock(album)
        let target: AlbumOrderTarget = to > from ? .after(order[to - 1].title) : .before(order[to + 1].title)
        library = try library.movingAlbum(album.title, target)
        recordChange(.albumMoved(album: album.title, from: from, to: to))
    }

    /// The title as the track list shows it (`TrackRow.displayTitle`).
    static func displayTitle(_ track: ITTrack) -> String {
        let title = track.title ?? ""
        return title.isEmpty ? "Untitled" : title
    }
}
