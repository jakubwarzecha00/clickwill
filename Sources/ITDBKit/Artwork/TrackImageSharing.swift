import Foundation

/// An album image that tracks without their own image record should share.
public struct TrackImageShare: Sendable, Equatable {
    public let album: String
    /// The image whose slices the new records reuse.
    public let imageID: UInt32
    /// `persistentID`s of the album's tracks that have no image record yet.
    public let tracks: [UInt64]
}

extension ArtworkLibrary {
    /// Albums whose artwork is missing from some of their tracks - for an iPod that finds
    /// artwork by the track (`IPodDevice.findsArtworkByTrack`).
    ///
    /// Only where it is unambiguous: every image the album already has uses the same
    /// slices, i.e. the album has one picture. An album with several different pictures
    /// is skipped - guessing would put the wrong artwork under a song.
    public func trackImageShares(in library: ITLibrary) -> [TrackImageShare] {
        let byTrack = indexedByTrack()
        let albums = Dictionary(grouping: library.tracks, by: { $0.album ?? "" })
        return albums.keys.sorted().compactMap { album in
            let tracks = albums[album] ?? []
            let images = tracks.compactMap { byTrack[$0.persistentID] }
            guard let first = images.min(by: { $0.id < $1.id }) else { return nil }
            let slices = Set(images.map(\.sliceSignature))
            guard slices.count == 1 else { return nil }
            let missing = tracks.filter { byTrack[$0.persistentID] == nil }.map(\.persistentID)
            guard !missing.isEmpty else { return nil }
            return TrackImageShare(album: album, imageID: first.id, tracks: missing)
        }
    }
}

extension ArtworkImage {
    /// The image's slices in the `.ithmb` files: format and offset of every variant.
    /// Two records with the same signature show the same pixels.
    var sliceSignature: [String] {
        variants.map { "\($0.correlationID)@\($0.byteOffset)" }.sorted()
    }
}
