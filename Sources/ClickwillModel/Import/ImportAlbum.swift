import Foundation
import ITDBKit

/// An album in the add sheet: files that go to the iPod as one album.
public struct ImportAlbum: Identifiable, Sendable {
    /// The group identifier - of the first file the rest were attached to.
    public let id: UUID
    /// Tracks in disc and track order.
    public let songs: [AudioImport.Candidate]

    /// Groups in the order in which the files came. `groupOf`: file -> the group
    /// it was attached to; a file without an entry is its own group.
    /// Within a group: disc number, track number, and when there are no numbers -
    /// the order in which the files came.
    public static func grouping(_ candidates: [AudioImport.Candidate], groupOf: [UUID: UUID]) -> [ImportAlbum] {
        var order: [UUID] = []
        var grouped: [UUID: [AudioImport.Candidate]] = [:]
        for candidate in candidates {
            let key = groupOf[candidate.id] ?? candidate.id
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(candidate)
        }
        return order.map { key in
            let songs = grouped[key, default: []].enumerated().sorted { left, right in
                let a = left.element.draft, b = right.element.draft
                if a.discNumber != b.discNumber { return a.discNumber < b.discNumber }
                if a.trackNumber != b.trackNumber, a.trackNumber > 0, b.trackNumber > 0 { return a.trackNumber < b.trackNumber }
                return left.offset < right.offset
            }.map(\.element)
            return ImportAlbum(id: key, songs: songs)
        }
    }
}

/// Album fields on the iPod that a file attached to this album receives.
public struct AlbumFields: Sendable, Equatable {
    public let album: String?
    public let albumArtist: String?
    public let artist: String?
    public let isCompilation: Bool
}
