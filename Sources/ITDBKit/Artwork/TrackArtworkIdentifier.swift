import Foundation

/// The field at 0x160 of the `mhit` record - the **image record identifier** the
/// track points to. This is the path the iPod takes to find artwork for the
/// song playing.
///
/// The history of this field is a history of four wrong hypotheses. An album
/// showed artwork in Cover Flow and not during playback.
/// We fixed, one after another, 0x7E, the 0x7C/0x80 pair, the second identifier at 0xA8,
/// the album record identity and field 0x124 - each fix landed in the database
/// correctly and **none changed anything on the device**. The reason was that
/// none of those fields is the one the iPod looks up.
///
/// Measurement on a Classic 7G, across 1622 tracks and 138 image records:
///
/// - 1558 tracks have a non-zero value here and **not one points to a
///   missing record** - zero dangling pointers out of 1558,
/// - the value range 101…260 matches the range of `mhii` identifiers
///   in `ArtworkDB` (101…266),
/// - the neighboring fields 0x15C and 0x164 have **a single value each**
///   across the whole library - so 0x160 is a separate field, not a piece of
///   something wider read from the middle,
/// - in 94 albums **every** track has its own album's image identifier here.
///
/// Zeros were found in exactly the albums that showed no artwork during playback:
/// "Pablo Honey" (image 264), "Patient Number 9" (265) and "Ordinary Man" (266)
/// on all tracks, "Ok Computer" (251) on twelve out of thirteen.
/// Identifiers 261…266 are the six newest images in the database and **no track
/// pointed to them**.
///
/// Hence the split in the symptom that looked like a contradiction for a long time:
/// Cover Flow links an image to an album through the record owner (`mhii` 0x14 =
/// track `persistentID`), so it works with one track per album. The Now Playing
/// screen goes through 0x160, so it needs it in **every** track.
/// That is why on broken albums the artwork appeared for exactly the one track
/// that owned the image record - "Patient Number 9" 1 of 13,
/// "Ordinary Man" 1 of 16.
extension ITTrack {
    /// Image record identifier (`mhii` 0x10, `MhitLayout.artworkIdentifier`).
    /// Zero means "no pointer".
    public var artworkIdentifier: UInt32 { rawHeader[MhitLayout.artworkIdentifier] ?? 0 }

    /// `MhitLayout.artworkPresence`: 1 when the track points to an image, 2 when it does not.
    /// Measured on the Classic: in Apple's records 1610 tracks with a pointer
    /// have 1 here, and 8 without a pointer have 2. The exceptions (55 tracks with an image and a two)
    /// are only albums added or repaired by us and "Ok Computer"
    /// broken by Music - the Classic shows them anyway. Finder on the nano 2G,
    /// without `ArtworkDB`, sets 2 in all 13 tracks; older firmware
    /// may rely on it, so we stick to Apple's rule.
    public var artworkPresence: UInt8 { rawHeader[MhitLayout.artworkPresence] ?? 0 }

    /// Sets the image pointer together with its paired `artworkPresence`.
    public func settingArtworkIdentifier(_ value: UInt32) -> ITTrack {
        guard rawHeader.count >= MhitLayout.artworkIdentifier.range.upperBound else { return self }
        var copy = self
        copy.rawHeader.set(MhitLayout.artworkIdentifier, value)
        copy.rawHeader.set(MhitLayout.artworkPresence, value == 0 ? 2 : 1)
        return copy
    }
}

extension ITLibrary {
    /// Fills in the image record pointer where it is missing.
    ///
    /// We touch **only** tracks whose current pointer leads
    /// nowhere - zero, or an identifier that does not exist in `ArtworkDB`.
    /// A track pointing to an existing image stays untouched, even if
    /// it is not the album's dominant image: we measured albums that
    /// legitimately use several records at once ("I AM MUSIC" 112, 113 and 240,
    /// "Ken Carson intros" 256, 257 and 258). Overwriting them with one value
    /// would put someone else's artwork under a song.
    ///
    /// - Parameters:
    ///   - imageIdentifiersByAlbum: the image assigned to an album, only where
    ///     it is unambiguous.
    ///   - existingIdentifiers: all identifiers present in `ArtworkDB`.
    ///     Without them a healthy pointer cannot be told apart from a dangling one.
    public func repairingArtworkIdentifiers(
        imageIdentifiersByAlbum: [String: UInt32],
        existingIdentifiers: Set<UInt32>
    ) -> (library: ITLibrary, repaired: [String: Int]) {
        var repaired: [String: Int] = [:]
        let updated = mappingTracks { track in
            let album = track.album ?? ""
            guard let identifier = imageIdentifiersByAlbum[album] else { return track }
            guard !existingIdentifiers.contains(track.artworkIdentifier) else { return track }
            repaired[album, default: 0] += 1
            return track.settingArtworkIdentifier(identifier)
        }
        return (updated, repaired)
    }
}

extension ArtworkLibrary {
    /// All image record identifiers in the database.
    public var imageIdentifiers: Set<UInt32> { Set(images.map(\.id)) }

    /// The image assigned to an album - where all of the album's records show
    /// one picture.
    ///
    /// One record per album is the iPod classic. On an iPod that finds artwork by
    /// the track (nano 2G) every song has its own record, all with the same slices
    /// (`trackImageShares`); the album then points to the lowest identifier, the
    /// record the others were copied from. Records with different slices are
    /// different pictures: such an album is skipped for the same reason
    /// `imageSourcesByAlbum` skips it - there is no way to tell which of them a
    /// track should point to, and guessing here means putting the wrong artwork
    /// under it.
    public func imageIdentifiersByAlbum(in library: ITLibrary) -> [String: UInt32] {
        let byTrack = indexedByTrack()
        var found: [String: [UInt32: ArtworkImage]] = [:]
        for track in library.tracks {
            guard let image = byTrack[track.persistentID] else { continue }
            found[track.album ?? "", default: [:]][image.id] = image
        }
        return found.compactMapValues { images in
            guard Set(images.values.map(\.sliceSignature)).count == 1 else { return nil }
            return images.keys.min()
        }
    }
}
