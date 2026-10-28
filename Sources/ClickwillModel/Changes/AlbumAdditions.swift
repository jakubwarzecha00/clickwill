import Foundation
import ITDBKit

/// Where in an album an added track should stand. The position counts on the album's
/// track list, as the app shows it.
public struct AlbumPlacement: Sendable, Equatable {
    public let album: String
    public let albumKey: AlbumKey
    public let index: Int
}

extension LibraryModel {

    /// Tracks waiting to be added to this album, in position order.
    public func pendingAdditions(for album: AlbumCard) -> [PendingAddition] {
        guard let library else { return [] }
        let all = library.tracks
        guard let key = album.trackIndices.first.flatMap({ $0 < all.count ? all[$0].albumKey : nil }) else { return [] }
        return changes.additions.filter { $0.placement?.albumKey == key }.sorted { ($0.placement?.index ?? 0) < ($1.placement?.index ?? 0) }
    }
}
