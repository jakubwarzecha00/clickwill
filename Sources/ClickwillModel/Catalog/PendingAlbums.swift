import Foundation
import CoreGraphics
import ImageIO
import ITDBKit

/// A new album from the add queue, before it reaches the iPod. It stands in Cover Flow
/// where it will land after the write, with a note that it is waiting - without this, after
/// "Add to Library" it is easy to conclude that adding failed.
public struct PendingAlbum: Identifiable, Sendable {
    public let key: AlbumKey
    /// The card for Cover Flow (`isPending`, without `mhit` records).
    public let card: AlbumCard
    /// Tracks in disc and track order.
    public let additions: [PendingAddition]
    public var id: AlbumID { card.id }
}

extension LibraryModel {

    /// Recomputes the new albums from the queue, and the Cover Flow and Albums lists with them. Called
    /// by every queue change and every card rebuild.
    func refreshPendingAlbums() {
        var order: [AlbumKey] = []
        var grouped: [AlbumKey: [PendingAddition]] = [:]
        // A track added to a specific album (placement) shows that album's view;
        // here only those that create an album.
        for addition in changes.additions where addition.placement == nil {
            let key = addition.draft.albumKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(addition)
        }
        let onDevice = Set(albums.map { AlbumKey(album: $0.title, albumArtist: $0.artist) })
        pendingAlbums = order.filter { !onDevice.contains($0) }.map { key in
            let songs = grouped[key, default: []].sorted {
                ($0.draft.discNumber, $0.draft.trackNumber) < ($1.draft.discNumber, $1.draft.trackNumber)
            }
            return PendingAlbum(key: key, card: pendingCard(key, songs), additions: songs)
        }
        coverFlowDisplay = pendingAlbums.isEmpty
            ? coverFlowAlbums
            : AlbumCatalog.coverFlowOrder(coverFlowAlbums + pendingAlbums.map(\.card))
        albumsDisplay = AlbumsMenu.order(coverFlowDisplay)
    }

    /// A pending album by card identifier.
    public func pendingAlbum(id: AlbumID) -> PendingAlbum? {
        pendingAlbums.first { $0.id == id }
    }

    private func pendingCard(_ key: AlbumKey, _ songs: [PendingAddition]) -> AlbumCard {
        let artworkID = Self.pendingArtworkID(for: key)
        if covers.image(for: artworkID) == nil,
           let source = songs.lazy.compactMap(\.cover).first,
           let image = Self.thumbnail(from: source) {
            covers.show(image, for: [artworkID])
        }
        var sortName = key.albumArtist
        if sortName.lowercased().hasPrefix("the ") { sortName.removeFirst(4) }
        var card = AlbumCard(
            id: .pending(key),
            trackIndices: [],
            trackIDs: [],
            title: key.album,
            artist: key.albumArtist,
            year: songs.map(\.draft.year).filter { $0 > 0 }.min(),
            genre: songs.first?.draft.genre,
            trackCount: songs.count,
            duration: songs.reduce(0) { $0 + TimeInterval($1.draft.durationMilliseconds) / 1000 },
            artworkTrackID: covers.image(for: artworkID) == nil ? nil : artworkID,
            missingFiles: 0,
            isCompilation: songs.contains { $0.draft.isCompilation },
            artistSortKey: sortName)
        card.hasArtwork = card.artworkTrackID != nil
        return card
    }

    /// A stable artwork identifier for a pending card (FNV-1a of the album
    /// and artist). Real track identifiers are random over 64 bits,
    /// so a collision is practically impossible.
    nonisolated static func pendingArtworkID(for key: AlbumKey) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "pending:\(key.album)\u{0}\(key.albumArtist)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// Artwork for the preview: a 600 px thumbnail, without decoding the full scan.
    nonisolated static func thumbnail(from source: AudioImport.CoverSource) -> CGImage? {
        let imageSource: CGImageSource?
        switch source {
        case .file(let url): imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .embedded(let data): imageSource = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let imageSource else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 600,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }
}
