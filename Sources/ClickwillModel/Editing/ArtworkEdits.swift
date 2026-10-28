import Foundation
import CoreGraphics
import ImageIO
import ITDBKit

/// An artwork replacement request - waiting for the write.
struct ArtworkReplacementJob: Sendable {
    let album: String
    let slots: [ArtworkReplacement.Slot]
    let trackIDs: [UInt64]
    let image: CGImage
}

/// A first-artwork request: new slots and a record, owner = the album's first
/// track, then pointed to in `mhia`.
struct ArtworkAdditionJob: Sendable {
    let album: String
    let ownerPersistentID: UInt64
    let trackIDs: [UInt64]
    let trackCount: Int
    let sourceByteCount: UInt32
    let image: CGImage
    /// A hardware trial of an image format outside the confirmed ones - only from `ipodctl`.
    var allowingUnverifiedFormats = false
}

/// An album image request for more tracks: a new `mhii` per track,
/// the same slices as `imageID`.
struct ArtworkSharingJob: Sendable {
    let album: String
    let imageID: UInt32
    let trackIDs: [UInt64]
}

public enum ArtworkError: Error, CustomStringConvertible {
    case noExistingArtwork(String)
    case unreadableImage(URL)
    public var description: String {
        switch self {
        case .noExistingArtwork(let album): "no ArtworkDB to add a cover to \(album)"
        case .unreadableImage(let url): "unreadable image \(url.lastPathComponent)"
        }
    }
}

extension LibraryModel {

    /// Loads an image from a file (PNG, JPEG, HEIC...) through ImageIO.
    public static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw ArtworkError.unreadableImage(url) }
        return image
    }
}

/// Album artwork. Preview right away, the device during the write.
extension LibraryEditor {

    /// Album artwork. An album with artwork: a replacement in place of the existing
    /// slices. An album without artwork: new slots and an `mhii` record for the first
    /// track, a pointer in `mhia`.
    mutating func setArtwork(for album: AlbumCard, image: CGImage, sourceByteCount: UInt32) throws {
        guard let album = current(album) else { return }
        let byTrack = artwork?.indexedByTrack() ?? [:]
        let tracks = records(of: album)
        guard let owner = tracks.first else { return }
        let slots = ArtworkReplacement.slots(for: tracks.compactMap { byTrack[$0.persistentID] })

        if !slots.isEmpty {
            let ids = tracks.filter { byTrack[$0.persistentID] != nil }.map(\.persistentID)
            changes.queueCoverReplacement(image, slots: slots, trackIDs: ids, album: album.title, for: album.id)
            preview(image, for: ids)
        } else {
            // First artwork needs formats that only an existing ArtworkDB knows.
            guard artwork?.images.isEmpty == false else { throw ArtworkError.noExistingArtwork(album.title) }
            changes.queueFirstCover(image, sourceByteCount: sourceByteCount, owner: owner, tracks: tracks,
                                    album: album.title, for: album.id)
            preview(image, for: tracks.map(\.persistentID))
        }
    }
}
