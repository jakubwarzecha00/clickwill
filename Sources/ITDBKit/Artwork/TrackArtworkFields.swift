import Foundation

/// Artwork fields in the track record (`mhit`), i.e. how the iPod knows
/// that **this song** has artwork.
///
/// This is different from `ArtworkDB`. That is where the image and its coverage live
/// (`mhii` 0x38, how many tracks of the album it applies to). Here there are three fields in the track itself:
///
/// - **0x7C** (16 bits) - artwork count,
/// - **0x7E** (16 bits) - `artworkMarker`, always `0xFFFF` from iTunes,
/// - **0x80** (32 bits) - source size in bytes.
///
/// Measured on a Classic 7G across 1642 records: **every one**
/// of the 1604 records written by iTunes has `0xFFFF` at 0x7E - including
/// eight that have zero at 0x7C. Only 38 records added by this app held
/// `0x0000`, and exactly those albums showed artwork in Cover Flow
/// but not for the song playing.
///
/// The cause was mundane: the generator wrote **four** zero bytes at 0x7C,
/// and 0x7C is a two-byte field. The second two bytes of that write landed
/// in 0x7E and wiped the marker.
extension ITTrack {
    /// The value iTunes keeps at 0x7E in every record.
    public static let artworkMarker: UInt16 = 0xFFFF

    /// The marker at `MhitLayout.artworkMarker` as it lies in the record.
    public var artworkMarker: UInt16 { rawHeader[MhitLayout.artworkMarker] ?? 0 }

    /// Whether the record looks the way an iTunes record looks.
    public var hasArtworkMarker: Bool { artworkMarker == Self.artworkMarker }

    /// Image source size (`mhii` 0x30) for an image of `pictureBytes` bytes.
    ///
    /// Measured on the nano 2G: Finder writes at 0x80 exactly the length of the image
    /// in the file's APIC frame (125953 B), and a one at 0x7C; the Classic rule
    /// (`mhii` 0x30 = 0x80 + 0x7C) then gives 125954. The image size alone
    /// would satisfy the rule, but would be one less than Apple's.
    public static func imageSourceByteCount(pictureBytes: UInt32, count: UInt16 = 1) -> UInt32 {
        pictureBytes &+ UInt32(count)
    }

    /// The size the track record should declare for an image of the given
    /// source size. See `ITLibrary.artworkSizeRule`.
    public static func declaredSize(forImageSource source: UInt32, count: UInt16) -> UInt32 {
        source >= UInt32(count) ? source - UInt32(count) : 0
    }

    /// Whether the record points to an image of this source size.
    public func pointsAtImage(sourceByteCount: UInt32) -> Bool {
        UInt32(embeddedArtworkCount) + embeddedArtworkSize == sourceByteCount
    }

    /// Sets all artwork fields for an image of the given source size
    /// (`mhii` 0x30). A `count` of zero means "no artwork", but the marker stays
    /// anyway - iTunes sets it whether or not there is artwork.
    public func markingArtwork(imageSourceByteCount: UInt32, count: UInt16 = 1) -> ITTrack {
        var copy = self
        let size = Self.declaredSize(forImageSource: imageSourceByteCount, count: count)
        copy.embeddedArtworkCount = count
        copy.embeddedArtworkSize = size
        copy.writeArtworkFields(count: count, sourceByteCount: size)
        return copy
    }

    /// The marker alone, without touching the count and size - for repairing records
    /// that are fine apart from it.
    public func restoringArtworkMarker() -> ITTrack {
        guard !hasArtworkMarker else { return self }
        var copy = self
        copy.writeArtworkFields(count: embeddedArtworkCount, sourceByteCount: embeddedArtworkSize)
        return copy
    }

    /// All three fields or none - a header shorter than the last of them is left alone.
    private mutating func writeArtworkFields(count: UInt16, sourceByteCount: UInt32) {
        guard rawHeader.count >= MhitLayout.artworkSourceSize.range.upperBound else { return }
        rawHeader.set(MhitLayout.artworkCount, count)
        rawHeader.set(MhitLayout.artworkMarker, Self.artworkMarker)
        rawHeader.set(MhitLayout.artworkSourceSize, sourceByteCount)
    }
}

extension ITLibrary {
    /// Marks **every** track of the album as having artwork.
    ///
    /// The image record and its coverage alone are not enough: coverage tells the iPod
    /// how many tracks the image applies to, but during playback the device also looks
    /// at the track record. An album added without this showed artwork in
    /// Cover Flow, but not for the song.
    public func markingAlbumArtwork(album title: String, sourceByteCount: UInt32, count: UInt16 = 1) -> ITLibrary {
        mappingTracks { track in
            guard (track.album ?? "") == title else { return track }
            return track.markingArtwork(imageSourceByteCount: sourceByteCount, count: count)
        }
    }

    /// Repairs tracks that point to an image with a source size that
    /// does not exist in `ArtworkDB`.
    ///
    /// The rule linking a track record to an image record, measured on the device
    /// (Classic 7G) across 1612 tracks: **`mhii` 0x30 = 0x80 + 0x7C**.
    /// It is not an approximation - the distribution of differences matches the distribution
    /// of 0x7C record for record (171 to 171, 55 to 55, 1 to 1, 14 to 14). 1555 tracks
    /// satisfy it. The other 57 are 44 added by this app and
    /// 12 "Ok Computer" tracks pointing to size 125546 - an image of that
    /// size has not been in the database **since the first backup
    /// on August 21**, so Apple Music left it there, not us.
    ///
    /// We repair only when the album has an image that can be pointed to.
    /// A track without an image stays untouched - there is nothing to repair and
    /// nothing to guess from.
    public func repairingArtworkSources(imageSourcesByAlbum: [String: UInt32]) -> (library: ITLibrary, repaired: [String: Int]) {
        let available = Set(imageSourcesByAlbum.values)
        var repaired: [String: Int] = [:]
        let updated = mappingTracks { track in
            let album = track.album ?? ""
            guard let source = imageSourcesByAlbum[album] else { return track }
            // A track that already points to some existing image stays as it is -
            // an album with several images may legitimately have different values.
            guard !available.contains(UInt32(track.embeddedArtworkCount) + track.embeddedArtworkSize) else { return track }
            repaired[album, default: 0] += 1
            let count = max(track.embeddedArtworkCount, 1)
            return track.markingArtwork(imageSourceByteCount: source, count: count)
        }
        return (updated, repaired)
    }

    /// Restores the 0x7E marker wherever it is missing and reports how many
    /// records were affected. The repair is safe for records without artwork,
    /// because iTunes sets `0xFFFF` there regardless.
    public func repairingArtworkMarkers() -> (library: ITLibrary, repaired: Int) {
        let broken = tracks.count { !$0.hasArtworkMarker }
        guard broken > 0 else { return (self, 0) }
        return (mappingTracks { $0.restoringArtworkMarker() }, broken)
    }
}

extension ArtworkImage {
    /// Image source size (`MhiiLayout.sourceByteCount`). This is what the
    /// track record sees through the artwork count and source size (`MhitLayout`).
    public var sourceByteCount: UInt32 { rawHeader[MhiiLayout.sourceByteCount] ?? 0 }
}

extension ArtworkLibrary {
    /// Artwork source size per album - only where it is unambiguous.
    ///
    /// An album with several different images is skipped: there is no way to tell
    /// which of them a track should point to, and guessing here would mean
    /// putting the wrong artwork under a song.
    public func imageSourcesByAlbum(in library: ITLibrary) -> [String: UInt32] {
        let byTrack = indexedByTrack()
        var found: [String: Set<UInt32>] = [:]
        for track in library.tracks {
            guard let image = byTrack[track.persistentID], image.sourceByteCount > 0 else { continue }
            found[track.album ?? "", default: []].insert(image.sourceByteCount)
        }
        return found.compactMapValues { $0.count == 1 ? $0.first : nil }
    }
}
