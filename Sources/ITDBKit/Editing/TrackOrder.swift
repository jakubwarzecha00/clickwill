import Foundation

/// Where to insert a moved track within an album.
public enum TrackOrderTarget: Sendable {
    case before(UInt32)
    case after(UInt32)
    case atIndex(Int)
}

public enum TrackOrderError: Error, CustomStringConvertible {
    case noBrowseIndex
    case albumNotFound(String)
    case albumSplit(String, blocks: Int)
    case trackNotInAlbum(UInt32, album: String)
    case wrongTrackSet(expected: Int, got: Int)
    case indexOutOfRange(Int, tracks: Int)
    case permutationBroken

    public var description: String {
        switch self {
        case .noBrowseIndex: return "This iPod's library has no album list yet. Sync it once with Music, then try again."
        case .albumNotFound(let name): return "“\(name)” isn't in the iPod's album list."
        case .albumSplit(let name, let blocks):
            return "“\(name)” is split into \(blocks) parts on the iPod. Merge them first, from the album."
        case .trackNotInAlbum(let id, let album): return "Song \(id) isn't part of “\(album)”. Nothing was changed."
        case .wrongTrackSet(let expected, let got):
            return "The new order has \(got) songs, but the album has \(expected). Nothing was changed."
        case .indexOutOfRange(let index, let tracks): return "Position \(index) is past the end of the album (\(tracks) songs)."
        case .permutationBroken: return "Clickwill stopped this change because the new song order didn't check out. Nothing was changed. Choose Send Feedback so I can look into it."
        }
    }
}

extension ITLibrary {

    /// The album's tracks in the order in which the device will show them.
    public func trackOrder(album name: String) throws -> [ITTrack] {
        let block = try singleBlock(album: name)
        let all = tracks
        return block.trackIndices.map { all[$0] }
    }

    /// Imposes the order of tracks in an album.
    ///
    /// Permutes only the run of the table that belongs to this album, so the
    /// alphabetical jump bar stays untouched. It concerns the album table - the one
    /// Cover Flow and the Albums menu use. The Artists -> album path has
    /// its own table, in which featured artists split the album into piles anyway.
    public func settingTrackOrder(album name: String, uniqueIDs: [UInt32]) throws -> ITLibrary {
        guard let index = browseIndex(.album) else { throw TrackOrderError.noBrowseIndex }
        let block = try singleBlock(album: name)
        let all = tracks

        let current = block.trackIndices.map { all[$0].uniqueID }
        guard uniqueIDs.count == current.count, Set(uniqueIDs) == Set(current) else {
            throw TrackOrderError.wrongTrackSet(expected: current.count, got: uniqueIDs.count)
        }
        let position = Dictionary(uniqueKeysWithValues: block.trackIndices.map { (all[$0].uniqueID, $0) })

        var entries = index.entries
        for (offset, id) in uniqueIDs.enumerated() {
            entries[block.range.lowerBound + offset] = UInt32(position[id]!)
        }
        guard Set(entries) == Set(index.entries), entries.count == index.entries.count else {
            throw TrackOrderError.permutationBroken
        }
        return replacingBrowseIndex(.album, entries: entries)
    }

    /// Moves one track within its album.
    public func movingTrack(_ id: UInt32, in album: String, _ target: TrackOrderTarget) throws -> ITLibrary {
        var order = try trackOrder(album: album).map(\.uniqueID)
        guard let from = order.firstIndex(of: id) else {
            throw TrackOrderError.trackNotInAlbum(id, album: album)
        }
        order.remove(at: from)

        let insertion: Int
        switch target {
        case .before(let other):
            guard let anchor = order.firstIndex(of: other) else {
                throw TrackOrderError.trackNotInAlbum(other, album: album)
            }
            insertion = anchor
        case .after(let other):
            guard let anchor = order.firstIndex(of: other) else {
                throw TrackOrderError.trackNotInAlbum(other, album: album)
            }
            insertion = anchor + 1
        case .atIndex(let position):
            guard (0...order.count).contains(position) else {
                throw TrackOrderError.indexOutOfRange(position, tracks: order.count)
            }
            insertion = position
        }
        order.insert(id, at: insertion)
        return try settingTrackOrder(album: album, uniqueIDs: order)
    }

    /// Assigns track numbers 1...N according to display order and sets
    /// the track count to N. This is metadata, so it survives Music regenerating the tables -
    /// and then Music lays out the album exactly as it is in the table now.
    /// Disc numbers are zeroed: after renumbering the album is one disc.
    public func renumberingTracks(album name: String) throws -> ITLibrary {
        let order = try trackOrder(album: name).map(\.uniqueID)
        let numbers = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, UInt32($0.offset + 1)) })
        let total = UInt32(order.count)
        return mappingTracks { track in
            guard let number = numbers[track.uniqueID] else { return track }
            var copy = track
            copy.trackNumber = number
            copy.totalTracks = total
            copy.discNumber = 0
            copy.totalDiscs = 0
            return copy
        }
    }

    private func singleBlock(album name: String) throws -> AlbumBlock {
        let matching = albumOrder().filter { $0.album == name }
        guard let block = matching.first else { throw TrackOrderError.albumNotFound(name) }
        guard matching.count == 1 else { throw TrackOrderError.albumSplit(name, blocks: matching.count) }
        return block
    }
}
