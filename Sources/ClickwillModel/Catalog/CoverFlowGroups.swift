import Foundation
import ITDBKit

/// A group in Cover Flow: one album artist, or "Compilations", or
/// "Unknown Artist". The group order is the order on the iPod's strip.
public struct CoverFlowGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Int, Hashable, Sendable {
        case artist = 0
        case numeric = 1
        case compilations = 2
        case unknown = 3
    }
    public let id: String
    public let kind: Kind
    public let title: String
    /// The artist's sort key. The group's place cannot be changed: the iPod
    /// places artists in Cover Flow itself (checked on the device).
    public let sortKey: String
    public let albums: [AlbumCard]

}

extension LibraryModel {

    /// Cover Flow cut into groups, in strip order.
    public var coverFlowGroups: [CoverFlowGroup] {
        var groups: [CoverFlowGroup] = []
        var current: (key: String, kind: CoverFlowGroup.Kind, title: String, albums: [AlbumCard])? = nil

        func flush() {
            guard let group = current else { return }
            groups.append(CoverFlowGroup(id: "\(group.kind.rawValue)#\(group.key)", kind: group.kind,
                                         title: group.title, sortKey: group.key, albums: group.albums))
            current = nil
        }

        for album in coverFlowAlbums {
            let kind: CoverFlowGroup.Kind
            let key: String
            let title: String
            if album.isCompilation {
                kind = .compilations; key = ""; title = "Compilations"
            } else {
                let folded = album.artistSortKey.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                if let first = folded.first(where: { $0.isLetter || $0.isNumber }) {
                    kind = first.isASCII && first.isLetter ? .artist : .numeric
                    key = folded
                    title = album.displayArtist
                } else {
                    kind = .unknown; key = ""; title = "Unknown Artist"
                }
            }
            if let open = current, open.kind == kind, open.key == key {
                current!.albums.append(album)
            } else {
                flush()
                current = (key, kind, title, [album])
            }
        }
        flush()
        return groups
    }
}
