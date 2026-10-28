import Foundation

/// A continuous run of the browse table that belongs to one album.
///
/// The device shows such a run as one menu item. The same album can
/// appear in several blocks if its tracks do not lie next to each other in the table -
/// that is exactly what a damaged table looks like.
public struct AlbumBlock: Sendable, Identifiable {
    /// Block number in display order.
    public let id: Int
    public let album: String
    public let artist: String
    /// Positions in the browse table.
    public let range: Range<Int>
    /// Numbers of the `mhit` records belonging to the block, in display order.
    public let trackIndices: [Int]

    public var trackCount: Int { range.count }
}

/// Where to insert the moved block.
public enum AlbumOrderTarget: Sendable {
    case before(String)
    case after(String)
    /// At the very start of the letter the block belongs to.
    case startOfLetter
    /// At the position with this number in block order (counting after the block is removed).
    case atIndex(Int)
}

/// What to do with the alphabetical jump bar after reordering.
public enum JumpTablePolicy: String, Codable, Sendable {
    /// Compute it from the actual layout. For alphabetical order this gives a bar
    /// identical to the one iTunes writes; for an arbitrary order letters repeat.
    case derived
    /// One entry without a letter covering everything - the format the device itself
    /// writes for criteria without values. A candidate variant for an arbitrary
    /// order, until we know whether repeating letters are tolerated.
    case flat
}

public enum AlbumOrderError: Error, CustomStringConvertible {
    case noBrowseIndex
    case albumNotFound(String)
    case albumAmbiguous(String, blocks: Int)
    case indexOutOfRange(Int, blocks: Int)
    case permutationBroken

    public var description: String {
        switch self {
        case .noBrowseIndex:
            return "This iPod's library has no album list yet. Sync it once with Music, then try again."
        case .albumNotFound(let name):
            return "“\(name)” isn't in the iPod's album list."
        case .albumAmbiguous(let name, let blocks):
            return "“\(name)” is split into \(blocks) parts on the iPod. Merge them first, from the album."
        case .indexOutOfRange(let index, let blocks):
            return "Position \(index) is past the end of the list of \(blocks) albums."
        case .permutationBroken:
            return "Clickwill stopped this change because the new album order didn't check out. Nothing was changed. Choose Send Feedback so I can look into it."
        }
    }
}

extension ITLibrary {
    /// The browse table for a criterion, from the master playlist.
    public func browseIndex(_ criterion: BrowseIndex.Criterion) -> BrowseIndex? {
        masterPlaylist?.mhods.lazy.compactMap(BrowseIndex.init(mhod:)).first { $0.criterion == criterion }
    }

    public func jumpTable(_ criterion: BrowseIndex.Criterion) -> AlphabetJumpTable? {
        masterPlaylist?.mhods.lazy.compactMap(AlphabetJumpTable.init(mhod:)).first { $0.criterion == criterion }
    }

    /// Album blocks in the order in which the device will show them.
    public func albumOrder() -> [AlbumBlock] {
        guard let index = browseIndex(.album) else { return [] }
        let allTracks = tracks
        var blocks: [AlbumBlock] = []
        var start = 0
        var current: String? = nil
        var indices: [Int] = []

        func flush(end: Int) {
            guard let name = current, !indices.isEmpty else { return }
            let first = allTracks[indices[0]]
            blocks.append(AlbumBlock(id: blocks.count, album: name,
                                     artist: first.albumArtist ?? first.artist ?? "",
                                     range: start..<end, trackIndices: indices))
        }

        for (position, entry) in index.entries.enumerated() {
            let slot = Int(entry)
            guard slot < allTracks.count else { continue }
            let name = allTracks[slot].album ?? ""
            if name != current {
                flush(end: position)
                start = position
                current = name
                indices = []
            }
            indices.append(slot)
        }
        flush(end: index.entries.count)
        return blocks
    }

    /// Moves an album block in the browse table.
    ///
    /// Changes only the order - no track record is touched. The write
    /// goes into **both** copies of the master playlist, because the database keeps it in
    /// `mhsd` sections of type 2 and 3, and letting them drift apart leaves the database inconsistent. The
    /// alphabetical jump bar is recomputed from the layout after the change.
    public func movingAlbum(
        _ name: String, _ target: AlbumOrderTarget, jumpTable policy: JumpTablePolicy = .derived
    ) throws -> ITLibrary {
        guard let index = browseIndex(.album) else { throw AlbumOrderError.noBrowseIndex }
        let blocks = albumOrder()

        let matching = blocks.filter { $0.album == name }
        guard let moved = matching.first else { throw AlbumOrderError.albumNotFound(name) }
        guard matching.count == 1 else {
            throw AlbumOrderError.albumAmbiguous(name, blocks: matching.count)
        }

        // Block order after taking out the one being moved.
        var order = blocks.filter { $0.id != moved.id }
        let insertion: Int
        switch target {
        case .before(let other):
            guard let anchor = order.firstIndex(where: { $0.album == other }) else {
                throw AlbumOrderError.albumNotFound(other)
            }
            insertion = anchor
        case .after(let other):
            guard let anchor = order.lastIndex(where: { $0.album == other }) else {
                throw AlbumOrderError.albumNotFound(other)
            }
            insertion = anchor + 1
        case .startOfLetter:
            let code = albumLetterCode(moved)
            insertion = order.firstIndex { albumLetterCode($0) == code } ?? order.count
        case .atIndex(let position):
            guard (0...order.count).contains(position) else {
                throw AlbumOrderError.indexOutOfRange(position, blocks: order.count)
            }
            insertion = position
        }
        order.insert(moved, at: insertion)

        return try replacingAlbumOrder(order, original: index, jumpTable: policy)
    }

    /// Writes the new block order: the table and the jump bar, in both copies.
    func replacingAlbumOrder(
        _ order: [AlbumBlock], original index: BrowseIndex, jumpTable policy: JumpTablePolicy
    ) throws -> ITLibrary {
        let entries = order.flatMap { $0.trackIndices.map(UInt32.init) }
        guard Set(entries) == Set(index.entries), entries.count == index.entries.count else {
            throw AlbumOrderError.permutationBroken
        }

        var result = replacingBrowseIndex(.album, entries: entries)
        if let jump = jumpTable(.album) {
            let rebuilt: AlphabetJumpTable
            switch policy {
            case .derived:
                rebuilt = jump.rebuilt(fromRuns: order.map { (albumLetterCode($0), $0.trackCount) })
            case .flat:
                rebuilt = jump.flattened(total: entries.count)
            }
            result = result.replacingJumpTable(.album, with: rebuilt)
        }
        return result
    }

    /// The letter code in the jump bar for a block - following the rules visible in bars
    /// written by iTunes: leading non-alphanumeric characters are skipped,
    /// a Latin letter gives its uppercase form, a digit and any other script `'0'`,
    /// an empty name `0`.
    public func albumLetterCode(_ block: AlbumBlock) -> UInt32 {
        Self.letterCode(for: albumSortKey(block))
    }

    static func letterCode(for key: String) -> UInt32 {
        let folded = key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard let first = folded.first(where: { $0.isLetter || $0.isNumber }) else {
            return AlphabetJumpTable.empty
        }
        if first.isASCII, first.isLetter, let scalar = first.uppercased().unicodeScalars.first {
            return scalar.value
        }
        return AlphabetJumpTable.digitsAndOther
    }

    /// Replaces the jump bar in all copies of the master playlist.
    func replacingJumpTable(_ criterion: BrowseIndex.Criterion, with table: AlphabetJumpTable) -> ITLibrary {
        var copy = self
        copy.sections = sections.map { section in
            guard case .playlists(let playlists) = section.content else { return section }
            var updated = section
            updated.content = .playlists(playlists.map { playlist in
                guard playlist.isMaster else { return playlist }
                var rebuilt = playlist
                rebuilt.mhods = playlist.mhods.map { mhod in
                    guard let existing = AlphabetJumpTable(mhod: mhod), existing.criterion == criterion else {
                        return mhod
                    }
                    return table.mhod()
                }
                return rebuilt
            })
            return updated
        }
        return copy
    }

    /// Replaces the browse table in all copies of the master playlist.
    func replacingBrowseIndex(_ criterion: BrowseIndex.Criterion, entries: [UInt32]) -> ITLibrary {
        var copy = self
        copy.sections = sections.map { section in
            guard case .playlists(let playlists) = section.content else { return section }
            var updated = section
            updated.content = .playlists(playlists.map { playlist in
                guard playlist.isMaster else { return playlist }
                var rebuilt = playlist
                rebuilt.mhods = playlist.mhods.map { mhod in
                    guard var index = BrowseIndex(mhod: mhod), index.criterion == criterion else {
                        return mhod
                    }
                    index.entries = entries
                    return index.mhod()
                }
                return rebuilt
            })
            return updated
        }
        return copy
    }
}
