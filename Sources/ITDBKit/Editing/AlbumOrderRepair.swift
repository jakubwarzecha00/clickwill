import Foundation

/// A repair plan for the album browse table.
///
/// We repair one specific kind of damage: an album whose tracks do not lie
/// next to each other in the table. The slot boundaries themselves are alphabetically correct -
/// a neighbor's content ended up in the wrong slots - so we do not recompute
/// the order from scratch. We only move content between existing ranges,
/// which leaves the alphabetical jump bar untouched.
public struct AlbumOrderRepair: Sendable {
    public struct Move: Sendable {
        public let album: String
        public let trackCount: Int
        /// Ranges in which the album's tracks lie now.
        public let from: [Range<Int>]
        /// The range in which they should lie.
        public let to: Range<Int>
        public let letter: Character?
        public var isNoop: Bool { from == [to] }
    }

    public let moves: [Move]
    /// How many table positions will change value.
    public let changedPositions: Int

    public var isEmpty: Bool { moves.allSatisfy(\.isNoop) }
}

public enum AlbumOrderRepairError: Error, CustomStringConvertible {
    case noBrowseIndex
    case noJumpTable
    case didNotConverge
    case letterMismatch(album: String, expected: Character?, available: [Character?])
    case sizeMismatch(letter: Character?, slots: Int, tracks: Int)
    case permutationBroken

    public var description: String {
        switch self {
        case .noBrowseIndex: return "This iPod's library has no album list yet. Sync it once with Music, then try again."
        case .noJumpTable: return "This iPod's library has no A to Z index for albums yet. Sync it once with Music, then try again."
        case .didNotConverge: return "Clickwill couldn't repair the album order. Nothing was changed. Choose Send Feedback so I can look into it."
        case .letterMismatch(let album, let expected, let available):
            return "Clickwill couldn't repair the album order: “\(album)” belongs under \(expected.map(String.init) ?? "?"), "
                + "but only \(available.map { $0.map(String.init) ?? "?" }.joined(separator: ", ")) had room. Nothing was changed."
        case .sizeMismatch(let letter, let slots, let tracks):
            return "Clickwill couldn't repair the album order: under \(letter.map(String.init) ?? "?") there are \(slots) places for \(tracks) songs. Nothing was changed."
        case .permutationBroken: return "Clickwill stopped the repair because the result didn't check out. Nothing was changed. Choose Send Feedback so I can look into it."
        }
    }
}

extension ITLibrary {

    /// The letter under which the album should lie. We take the first character of the
    /// sort field, because that - not the name itself - decides the place in the alphabet.
    static func albumLetter(sortKey: String) -> Character? {
        guard let first = sortKey.first else { return nil }
        let upper = Character(String(first).uppercased())
        return upper.isLetter ? upper : (first.isNumber ? "0" : nil)
    }

    func albumSortKey(_ block: AlbumBlock) -> String {
        let all = tracks
        guard let index = block.trackIndices.first, index < all.count else { return block.album }
        let track = all[index]
        let raw = track.sortAlbum ?? track.album ?? ""
        return raw.isEmpty ? block.album : raw
    }

    /// Works out what has to move where. Writes nothing.
    public func planAlbumOrderRepair() throws -> AlbumOrderRepair {
        guard browseIndex(.album) != nil else { throw AlbumOrderRepairError.noBrowseIndex }
        guard let jump = jumpTable(.album) else { throw AlbumOrderRepairError.noJumpTable }
        let blocks = albumOrder()

        // Starting point: albums lying in more than one block. That is a structural
        // defect, so we recognize it without any assumptions about collation.
        var affected = Set(
            Dictionary(grouping: blocks, by: \.album).filter { $0.value.count > 1 }.keys)
        guard !affected.isEmpty else { return AlbumOrderRepair(moves: [], changedPositions: 0) }

        /// Merges adjacent ranges into one.
        func merged(_ ranges: [Range<Int>]) -> [Range<Int>] {
            var out: [Range<Int>] = []
            for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if let last = out.last, last.upperBound == range.lowerBound {
                    out[out.count - 1] = last.lowerBound..<range.upperBound
                } else {
                    out.append(range)
                }
            }
            return out
        }

        // The set grows until the number of slots under each letter matches
        // the number of tracks that must go there. If space runs short, we pull in
        // the neighboring block - it is the one occupying slots someone else needs.
        var ranges: [Range<Int>] = []
        var converged = false
        for _ in 0..<32 {
            ranges = merged(blocks.filter { affected.contains($0.album) }.map(\.range))

            var slotsByLetter: [Character?: Int] = [:]
            for range in ranges {
                let letter = jump.section(containing: range.lowerBound)?.character
                slotsByLetter[letter, default: 0] += range.count
            }
            var tracksByLetter: [Character?: Int] = [:]
            for name in affected {
                let parts = blocks.filter { $0.album == name }
                let letter = Self.albumLetter(sortKey: albumSortKey(parts[0]))
                tracksByLetter[letter, default: 0] += parts.reduce(0) { $0 + $1.trackCount }
            }

            let short = tracksByLetter.first { slotsByLetter[$0.key, default: 0] < $0.value }
            guard let missing = short else { converged = true; break }

            // Add the block right after the last range of this letter.
            let ownRanges = ranges.filter { jump.section(containing: $0.lowerBound)?.character == missing.key }
            guard let last = ownRanges.last,
                  let next = blocks.first(where: { $0.range.lowerBound == last.upperBound })
            else { throw AlbumOrderRepairError.didNotConverge }
            affected.insert(next.album)
        }
        guard converged else { throw AlbumOrderRepairError.didNotConverge }

        // Assignment: under each letter albums are laid out alphabetically,
        // and that letter's ranges are joined into one run of slots.
        var rangesByLetter: [Character?: [Range<Int>]] = [:]
        for range in ranges {
            rangesByLetter[jump.section(containing: range.lowerBound)?.character, default: []].append(range)
        }
        var albumsByLetter: [Character?: [AlbumBlock]] = [:]
        for name in affected {
            let parts = blocks.filter { $0.album == name }
            albumsByLetter[Self.albumLetter(sortKey: albumSortKey(parts[0])), default: []].append(parts[0])
        }

        var moves: [AlbumOrderRepair.Move] = []
        for (letter, group) in albumsByLetter {
            guard let slots = rangesByLetter[letter] else {
                throw AlbumOrderRepairError.letterMismatch(
                    album: group[0].album, expected: letter,
                    available: rangesByLetter.keys.sorted { ($0.map(String.init) ?? "") < ($1.map(String.init) ?? "") })
            }
            let flattened = slots.sorted { $0.lowerBound < $1.lowerBound }.flatMap { Array($0) }
            let ordered = group.sorted { albumSortKey($0).lowercased() < albumSortKey($1).lowercased() }
            let needed = ordered.reduce(0) { total, block in
                total + blocks.filter { $0.album == block.album }.reduce(0) { $0 + $1.trackCount }
            }
            guard flattened.count == needed else {
                throw AlbumOrderRepairError.sizeMismatch(letter: letter, slots: flattened.count, tracks: needed)
            }

            var cursor = 0
            for block in ordered {
                let parts = blocks.filter { $0.album == block.album }
                let count = parts.reduce(0) { $0 + $1.trackCount }
                let target = flattened[cursor]..<(flattened[cursor] + count)
                moves.append(AlbumOrderRepair.Move(
                    album: block.album, trackCount: count,
                    from: parts.map(\.range).sorted { $0.lowerBound < $1.lowerBound },
                    to: target, letter: letter))
                cursor += count
            }
        }

        moves.sort { $0.to.lowerBound < $1.to.lowerBound }
        let changed = moves.filter { !$0.isNoop }.reduce(0) { $0 + $1.trackCount }
        return AlbumOrderRepair(moves: moves, changedPositions: changed)
    }

    /// Carries out the plan. Tracks within an album go by disc and track number;
    /// without numbers the order of records in the database decides.
    public func applyingAlbumOrderRepair(_ repair: AlbumOrderRepair) throws -> ITLibrary {
        guard let index = browseIndex(.album) else { throw AlbumOrderRepairError.noBrowseIndex }
        let all = tracks
        let entries = try Self.applying(repair.moves, to: index.entries) { left, right in
            let a = all[left], b = all[right]
            let discs = (a.discNumber, b.discNumber)
            if discs.0 != discs.1 { return discs.0 < discs.1 }
            let numbers = (a.trackNumber, b.trackNumber)
            if numbers.0 != numbers.1 { return numbers.0 < numbers.1 }
            return left < right
        }
        return replacingBrowseIndex(.album, entries: entries)
    }

    /// Moves content between ranges.
    ///
    /// The source is read from an **unchanged copy**, because the target ranges of some moves
    /// overlap the source ranges of others - the repair is a rotation, not a series of
    /// independent shifts. Reading from the table while modifying it would give
    /// values already overwritten.
    static func applying(
        _ moves: [AlbumOrderRepair.Move],
        to entries: [UInt32],
        orderedBy isBefore: (Int, Int) -> Bool
    ) throws -> [UInt32] {
        let source = entries
        var result = entries

        for move in moves {
            let ordered = move.from
                .flatMap { Array($0) }
                .map { Int(source[$0]) }
                .sorted(by: isBefore)
            guard ordered.count == move.to.count else {
                throw AlbumOrderRepairError.sizeMismatch(
                    letter: move.letter, slots: move.to.count, tracks: ordered.count)
            }
            for (offset, track) in ordered.enumerated() {
                result[move.to.lowerBound + offset] = UInt32(track)
            }
        }

        guard Set(result) == Set(source), result.count == source.count else {
            throw AlbumOrderRepairError.permutationBroken
        }
        return result
    }
}
