import Foundation

/// Adding tracks to the database.
///
/// The `mhit` record has a 624-byte header, of which we understand about fifty bytes.
/// The rest must not be zeroed "because we don't know", nor copied blindly -
/// that is why a new record is created **from an existing record of the same iPod**,
/// and we replace in it only what we have measured.
///
/// The template must be of the same kind. Measured on 1603 tracks of the device:
/// bytes 0x1D, 0x94-0x97, 0x14B, 0x195, 0x1EC and 0x229 are constant within one
/// format description, and differ between formats - so they carry the format, not the track.
/// The same measurement drives the template choice: among tracks of the right
/// kind we take the one with **the most zeros** in the fields we do not
/// overwrite. Someone else's value in an unknown field is worse than zero, because zero
/// in those fields occurs in databases written by iTunes, so the device knows it.
///
/// One field needed a separate decision: 0xA8 holds a second copy
/// of the persistent identifier (1578 of 1603 tracks have exactly the value from
/// 0x70 there, the rest zero). Copying it from the template would give the new track someone else's
/// identifier, so we set it together with 0x70.
extension ITLibrary {

    /// The template for a given file kind - the cleanest record we have.
    ///
    /// We deliberately do not reach for tracks described as "Purchased" and "Matched":
    /// they carry store flags that must not be faked for one's own file.
    /// `fileKind` recognizes only the four descriptions without store traces, so they
    /// drop out on their own.
    public func templateTrack(for kind: TrackFileKind) -> ITTrack? {
        tracks.filter { $0.fileKind == kind }
            .min { Self.templateNoise($0) < Self.templateNoise($1) }
    }

    /// A template for a kind this iPod does not have yet: the cleanest
    /// record of another kind from the same device, switched to `kind`
    /// in the four places of the format description and in the bytes of the measured profile.
    /// `nil` for a kind without a profile - then a refusal, as before.
    public func crossKindTemplate(for kind: TrackFileKind) -> ITTrack? {
        guard let profile = TrackKindProfile.measured[kind],
              let base = tracks.filter({ $0.fileKind != nil && $0.fileKind != kind })
                  .min(by: { Self.templateNoise($0) < Self.templateNoise($1) })
        else { return nil }
        var template = base.settingFileKind(kind)
        for (offset, value) in profile.bytes where offset < template.rawHeader.count {
            template.rawHeader[offset] = value
        }
        return template
    }

    /// How many template bytes will pass into the new record with someone else's non-zero value.
    static func templateNoise(_ track: ITTrack) -> Int {
        track.rawHeader.enumerated().reduce(0) { total, item in
            overwrittenOffsets.contains(item.offset) || item.element == 0 ? total : total + 1
        }
    }

    /// Bytes the generator sets itself - they do not count toward the template's "noise".
    static let overwrittenOffsets: Set<Int> = {
        typealias M = MhitLayout
        let ranges: [Range<Int>] = [
            RecordLayout.totalLength.range, M.mhodCount.range, M.uniqueID.range, M.visible.range,
            M.fileTypeCode.range, M.type1.range, M.mpegFlag.range, M.compilation.range, M.rating.range,
            M.dateModified.range, M.sizeBytes.range, M.durationMilliseconds.range, M.trackNumber.range,
            M.totalTracks.range, M.year.range, M.bitRate.range, M.sampleRate.range, M.playCount.range,
            M.unknown54.range, M.lastPlayed.range, M.discNumber.range, M.totalDiscs.range, M.dateAdded.range,
            M.persistentID.range, M.artworkCount.range, M.artworkMarker.range, M.artworkSourceSize.range,
            M.sampleRateFloat.range, M.unknown98.range, M.unknown9C.range, M.unknownA0.range,
            M.artworkPresence.range, M.secondaryPersistentID.range, M.albumRecordIndex.range,
            M.sizeBytesSecondary.range, M.losslessFlag.range, M.artworkIdentifier.range, M.uniqueIDPlusOne.range,
        ]
        return Set(ranges.joined())
    }()

    /// Builds a track record from the template. Does not touch the library.
    public func makingTrack(
        from draft: TrackDraft, template: ITTrack, uniqueID: UInt32, persistentID: UInt64,
        albumRecordIndex: UInt32, inheritingSortFieldsFrom sibling: ITTrack?, now: Date
    ) -> ITTrack {
        var track = template
        track.uniqueID = uniqueID
        track.persistentID = persistentID

        track.playCount = 0
        track.rating = 0
        track.lastPlayed = nil
        track.dateAdded = now
        track.trackNumber = draft.trackNumber
        track.totalTracks = draft.totalTracks
        track.discNumber = draft.discNumber
        track.totalDiscs = draft.totalDiscs
        track.year = draft.year
        track.isCompilation = draft.isCompilation
        track.albumRecordIndex = albumRecordIndex

        track.rawHeader.set(MhitLayout.uniqueID, uniqueID)
        track.rawHeader.set(MhitLayout.visible, 1)
        track.rawHeader.set(MhitLayout.dateModified, MacTime.value(from: now))
        track.rawHeader.set(MhitLayout.unknown54, 0)
        track.rawHeader.set(MhitLayout.persistentID, persistentID)
        // Second copy of the identifier - only where the device
        // uses it: the Classic has it in 1598 of 1623 tracks, Finder on the nano 2G
        // leaves zero here in all of them.
        track.rawHeader.set(MhitLayout.secondaryPersistentID, usesSecondaryPersistentID ? persistentID : 0)
        // Artwork: the artwork count is **16-bit**, and right after it sits
        // a separate word (the marker) that iTunes keeps at 0xFFFF in
        // all 1604 records on this device - including those without
        // artwork. Writing a four-byte zero at 0x7C wiped it together
        // with the count. Tracks created that way showed the album artwork
        // in Cover Flow, but not for the song itself.
        track.embeddedArtworkCount = 0
        track.embeddedArtworkSize = 0
        track.rawHeader.set(MhitLayout.artworkCount, 0)
        track.rawHeader.set(MhitLayout.artworkMarker, ITTrack.artworkMarker)
        track.rawHeader.set(MhitLayout.artworkSourceSize, 0)
        // An image record identifier inherited from the
        // template would point to **another album's** artwork, so we zero it
        // here, and `repairingArtworkIdentifiers` fills in the right value
        // once this album's image is in `ArtworkDB`.
        track.rawHeader.set(MhitLayout.artworkIdentifier, 0)
        track.rawHeader.set(MhitLayout.artworkPresence, 2)   // no image, as Apple does
        track.rawHeader.set(MhitLayout.unknown98, 0)
        track.rawHeader.set(MhitLayout.unknown9C, 0)
        track.rawHeader.set(MhitLayout.unknownA0, 0)
        track.rawHeader.set(MhitLayout.uniqueIDPlusOne, uniqueID &+ 1)

        // Text fields are built from scratch, in the order iTunes keeps constant
        // across all 1603 records: title, artist, album artist,
        // composer, album, genre, format description, comment, path, and at
        // the end the sort fields.
        var fields: [(MhodType, String?)] = [
            (.title, draft.title),
            (.artist, draft.artist),
            (.albumArtist, draft.albumArtist),
            (.composer, draft.composer),
            (.album, draft.album),
            (.genre, draft.genre),
            (.fileType, draft.kind.fileTypeDescription),
            (.comment, draft.comment),
            (.location, ITTrack.databaseLocation(fromFilesystemPath: draft.relativePath)),
        ]
        // Sort fields are inherited from the rest of the album. Without this the new track
        // would split the album into two covers - the device groups by exactly these.
        for type in [MhodType.sortTitle, .sortAlbum, .sortAlbumArtist, .sortArtist] {
            let value = type == .sortTitle ? nil : sibling?.fields[type]
            if let value { fields.append((type, value)) }
        }

        track.mhods = fields.compactMap { type, value in
            guard let value, !value.isEmpty else { return nil }
            return Mhod.text(type: type, value: value)
        }
        track.fields = Dictionary(uniqueKeysWithValues: track.mhods.compactMap { mhod in
            mhod.text.map { (mhod.type, $0) }
        })

        return track
            .replacingFile(relativePath: draft.relativePath, sizeBytes: draft.sizeBytes,
                           durationMilliseconds: draft.durationMilliseconds,
                           bitRate: draft.bitRate, sampleRate: draft.sampleRate, kind: draft.kind)
    }
}
