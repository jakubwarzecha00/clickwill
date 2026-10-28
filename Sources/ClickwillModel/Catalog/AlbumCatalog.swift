import Foundation
import ITDBKit

/// Album cards computed from the library, in two orders: the album
/// table (the Albums menu on the iPod) and the Cover Flow strip.
///
/// A plain value: it changes nothing and remembers no edits. After every library
/// change it is rebuilt (`LibraryModel.rebuildCards()`).
public struct AlbumCatalog: Sendable {
    /// The order from the album table - it governs the Albums menu and the track order.
    public let albums: [AlbumCard]
    /// The order in which Cover Flow shows covers on the iPod
    /// (`coverFlowOrder`). Groups as on the device: by album artist
    /// and album, compilations separately.
    public let coverFlow: [AlbumCard]

    /// Cards by identifier and by track - each track belongs to exactly
    /// one card in each of the lists.
    private let albumByID: [AlbumID: Int]
    private let coverFlowByID: [AlbumID: Int]
    private let albumByTrack: [UInt64: Int]
    private let coverFlowByTrack: [UInt64: Int]

    public static let empty = AlbumCatalog(albums: [], coverFlow: [])

    private init(albums: [AlbumCard], coverFlow: [AlbumCard]) {
        self.albums = albums
        self.coverFlow = coverFlow
        func byID(_ cards: [AlbumCard]) -> [AlbumID: Int] {
            Dictionary(cards.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        }
        func byTrack(_ cards: [AlbumCard]) -> [UInt64: Int] {
            Dictionary(cards.enumerated().flatMap { offset, card in card.trackIDs.map { ($0, offset) } },
                       uniquingKeysWith: { first, _ in first })
        }
        albumByID = byID(albums)
        coverFlowByID = byID(coverFlow)
        albumByTrack = byTrack(albums)
        coverFlowByTrack = byTrack(coverFlow)
    }

    /// `missingFiles`: tracks without a file on the iPod - for the count on the card.
    public init(library: ITLibrary, artwork: ArtworkLibrary?, missingFiles: Set<UInt32>) {
        let blocks = library.albumOrder()
        // Once per rebuild, not once per card: there are hundreds of cards (albums
        // and Cover Flow), and a rebuild runs every 50 tracks during the format scan.
        let builder = CardBuilder(tracks: library.tracks, byTrack: artwork?.indexedByTrack() ?? [:],
                                  missingFiles: missingFiles)
        self.init(albums: blocks.map { builder.card(title: $0.album, indices: $0.trackIndices, coversBlock: true) },
                  coverFlow: AlbumCatalog.coverFlowOrder(Self.coverFlowCards(blocks: blocks, builder: builder)))
    }

    /// The current version of a card - the same identity, and when it is gone (the
    /// anchor track disappeared, the album was merged with another), the card with the remaining tracks
    /// of this one. `nil` when no track of the card is left.
    public func current(_ album: AlbumCard) -> AlbumCard? {
        switch album.id {
        case .album:
            if let index = albumByID[album.id] { return albums[index] }
            if let index = album.trackIDs.lazy.compactMap({ albumByTrack[$0] }).first { return albums[index] }
            return nil
        case .coverFlowPart:
            if let index = coverFlowByID[album.id] { return coverFlow[index] }
            if let index = album.trackIDs.lazy.compactMap({ coverFlowByTrack[$0] }).first { return coverFlow[index] }
            return nil
        case .pending:
            return nil
        }
    }

    /// The album table block for a card - only for a card that is an album
    /// (`AlbumID.album`). A part of a block from Cover Flow has no single block.
    public func block(for album: AlbumCard) -> AlbumCard? {
        guard case .album = album.id else { return nil }
        return current(album)
    }

    public func index(of album: AlbumCard) -> Int? {
        guard let block = block(for: album) else { return nil }
        return albumByID[block.id]
    }

    /// The core (`settingTrackOrder`, `movingAlbum`, `renumberingTracks`) identifies
    /// an album by title - just like `ipodctl`. When a title has two blocks (a table
    /// defect or two different albums with the same name), there is no telling which one
    /// to change - a refusal instead of guessing.
    func requireSingleBlock(_ album: AlbumCard) throws {
        let blocks = albums.filter { $0.title == album.title }
        guard blocks.count == 1 else { throw AlbumOrderError.albumAmbiguous(album.title, blocks: blocks.count) }
    }

    // MARK: - Cover Flow

    /// Cover Flow groups by track: (album artist, album). For an album with a
    /// consistent artist this is the same block as in the table; tracks without an album
    /// spread out to their artists, and those with nothing go to the end.
    private static func coverFlowCards(blocks: [AlbumBlock], builder: CardBuilder) -> [AlbumCard] {
        struct Group {
            let title: String
            var indices: [Int]
            var blocks: Set<Int>
        }
        var groups: [Group] = []
        var position: [String: Int] = [:]
        for block in blocks {
            for slot in block.trackIndices {
                let track = builder.tracks[slot]
                let artist = track.isCompilation ? "\u{1}compilation" : artistSortKey(of: track)
                let key = artist + "\u{0}" + (track.album ?? "")
                if let index = position[key] {
                    groups[index].indices.append(slot)
                    groups[index].blocks.insert(block.id)
                } else {
                    position[key] = groups.count
                    groups.append(Group(title: track.album ?? "", indices: [slot], blocks: [block.id]))
                }
            }
        }
        // A Cover Flow card that covers exactly one table block has the
        // same tracks, and so the same identifier as the block's card - an edit
        // from Cover Flow lands in the album. Groups assembled from parts of blocks are
        // `AlbumID.coverFlowPart`.
        let blockSize = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0.trackIndices.count) })
        return groups.map { group in
            let wholeBlock = group.blocks.count == 1 && group.blocks.first.flatMap { blockSize[$0] } == group.indices.count
            return builder.card(title: group.title, indices: group.indices, coversBlock: wholeBlock)
        }
    }

    /// The strip order as the iPod lays it out. The iPod does it itself, on the fly, and
    /// reads neither the album table nor the sort fields (checked on an iPod
    /// Classic: a numbered sort album artist and tables by artist did not
    /// swap Black Sabbath and Aerosmith; The ultimate sin moved
    /// in the album table before Blizzard of Ozz stayed last in Cover Flow).
    /// Artists go alphabetically by name without a leading "The ", their albums
    /// alphabetically by title; letters first, then digits and other scripts.
    /// Compilations stand as a block at the end in album table order, followed by
    /// the unknown artist.
    public static func coverFlowOrder(_ albums: [AlbumCard]) -> [AlbumCard] {
        func rank(_ card: AlbumCard) -> (Int, String, String) {
            if card.isCompilation { return (2, "", "") }
            let artist = coverFlowName(card.artist)
            guard let first = artist.first(where: { $0.isLetter || $0.isNumber }) else { return (3, "", "") }
            return (first.isASCII && first.isLetter ? 0 : 1, artist, coverFlowName(card.title))
        }
        return albums.enumerated()
            .map { (offset: $0.offset, card: $0.element, key: rank($0.element)) }
            .sorted { lhs, rhs in
                if lhs.key != rhs.key { return lhs.key < rhs.key }
                return lhs.offset < rhs.offset
            }
            .map(\.card)
    }

    /// The name for comparisons on the strip: ignoring case and diacritics,
    /// without a leading "The ".
    static func coverFlowName(_ name: String) -> String {
        var folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if folded.hasPrefix("the ") { folded.removeFirst(4) }
        return folded
    }

    /// The artist group key: the album artist's sort field, then the artist's,
    /// then the name without a leading "The ".
    static func artistSortKey(of track: ITTrack?) -> String {
        guard let track else { return "" }
        if let sort = track.sortAlbumArtist, !sort.isEmpty { return sort }
        if track.albumArtist == nil, let sort = track.sortArtist, !sort.isEmpty { return sort }
        var name = track.effectiveAlbumArtist
        if name.lowercased().hasPrefix("the ") { name.removeFirst(4) }
        return name
    }
}

/// Assembles a card from the tracks of a block or group.
private struct CardBuilder {
    let tracks: [ITTrack]
    let byTrack: [UInt64: ArtworkImage]
    let missingFiles: Set<UInt32>

    /// `coversBlock`: the card is a whole block of the album table (`AlbumID.album`),
    /// not a part of it (`AlbumID.coverFlowPart`).
    func card(title: String, indices: [Int], coversBlock: Bool) -> AlbumCard {
        let members = indices.map { tracks[$0] }
        let ids = members.map(\.persistentID)
        let anchor = AlbumID.anchor(of: ids)
        let first = members.first
        // The track the card's artwork hangs on. An album without artwork gets
        // the first track as a hook - otherwise a preview of newly chosen artwork
        // would have nowhere to show, and the change would look like it failed,
        // even though it is in the queue.
        let artworkTrack = members.first { byTrack[$0.persistentID] != nil } ?? first
        var card = AlbumCard(
            id: coversBlock ? .album(anchor) : .coverFlowPart(anchor),
            trackIndices: indices,
            trackIDs: ids,
            title: title,
            artist: first?.effectiveAlbumArtist ?? "",
            year: members.map(\.year).filter { $0 > 0 }.min(),
            genre: first?.genre,
            trackCount: members.count,
            duration: members.reduce(0) { $0 + $1.duration },
            artworkTrackID: artworkTrack?.persistentID,
            missingFiles: members.filter { missingFiles.contains($0.uniqueID) }.count,
            isCompilation: members.contains(where: \.isCompilation),
            artistSortKey: AlbumCatalog.artistSortKey(of: first))
        card.hasArtwork = members.contains { byTrack[$0.persistentID] != nil }
        card.albumSortName = members.lazy.compactMap(\.sortAlbum).first { !$0.isEmpty }
        return card
    }
}
