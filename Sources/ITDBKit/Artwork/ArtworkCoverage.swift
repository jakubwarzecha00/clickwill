import Foundation

/// How many tracks of an album its artwork covers.
///
/// The `mhii` record carries at 0x38 the number of tracks it applies to - and
/// that number, not the mere existence of the record, decides whether the iPod
/// shows the album's artwork. Confirmed on the device: "Ok Computer" had one
/// image declaring 1 track out of 13 and showed no artwork; after raising the
/// value to 13 it did.
///
/// The sums add up where an album has several different images: DOPAMINE
/// 15 + 1 = 16 tracks, I AM MUSIC 26 + 1 + 1 + 1 = 29.
public enum ArtworkCoverage {

    public struct Album: Sendable {
        public let title: String
        public let artist: String
        /// How many tracks the album really has.
        public let trackCount: Int
        /// How many tracks its images declare in total.
        public let declared: Int
        public let imageIDs: [UInt32]
        /// Whether all images of the album carry the same pixels. Always true
        /// for a single image; with several it is checked only when we have
        /// access to the `.ithmb` files.
        public let imagesMatch: Bool

        public init(title: String, artist: String, trackCount: Int, declared: Int,
                    imageIDs: [UInt32], imagesMatch: Bool) {
            self.title = title
            self.artist = artist
            self.trackCount = trackCount
            self.declared = declared
            self.imageIDs = imageIDs
            self.imagesMatch = imagesMatch
        }

        public var isComplete: Bool { declared == trackCount }

        /// We repair an album where there is nothing to guess: it has either one
        /// image, or several that all show the same thing - then it does not
        /// matter which covers which track. An album with **different**
        /// images is left alone, because guessing would break something
        /// that works today.
        public var isRepairable: Bool {
            guard declared != trackCount, trackCount > 0, !imageIDs.isEmpty else { return false }
            return imageIDs.count == 1 || imagesMatch
        }

        /// New 0x38 values, so that the sum equals the number of tracks.
        /// The first image absorbs any surplus or shortfall; the others stay
        /// untouched, and each must cover at least one track.
        func repairedCounts(current: [UInt32: UInt32]) -> [UInt32: UInt32]? {
            guard isRepairable else { return nil }
            let others = imageIDs.dropFirst()
            let othersSum = others.reduce(0) { $0 + Int(current[$1] ?? 0) }
            let first = trackCount - othersSum
            guard first >= 1 else { return nil }
            return [imageIDs[0]: UInt32(first)]
        }
    }

    /// Coverage state for every album that has at least one image.
    ///
    /// `paths` is needed only to compare pixels for an album with several
    /// images; without it such an album is always treated as
    /// ambiguous.
    public static func audit(library: ITLibrary, artworkDB: Data, paths: IPodPaths? = nil) throws -> [Album] {
        let records = try ArtworkDBEditor.trackCounts(in: artworkDB)
        let byPersistentID = Dictionary(library.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first })

        var trackCounts: [String: Int] = [:]
        var artists: [String: String] = [:]
        for track in library.tracks {
            let album = track.album ?? ""
            trackCounts[album, default: 0] += 1
            if artists[album] == nil { artists[album] = track.effectiveAlbumArtist }
        }

        var declared: [String: (sum: Int, ids: [UInt32])] = [:]
        for record in records {
            guard let track = byPersistentID[record.ownerPersistentID] else { continue }
            let album = track.album ?? ""
            var entry = declared[album] ?? (0, [])
            entry.sum += Int(record.trackCount)
            entry.ids.append(record.imageID)
            declared[album] = entry
        }

        // We compare pixels only where it changes anything:
        // an album with several images and mismatched coverage.
        var variants: [UInt32: [ArtworkVariant]] = [:]
        if paths != nil,
           declared.contains(where: { $0.value.ids.count > 1 && $0.value.sum != (trackCounts[$0.key] ?? 0) }),
           let parsed = try? ArtworkDBParser.parse(artworkDB) {
            for image in parsed.images { variants[image.id] = image.variants }
        }

        return declared.map { album, entry in
            let ids = entry.ids.sorted()
            let match: Bool
            if ids.count == 1 {
                match = true
            } else if let paths, entry.sum != (trackCounts[album] ?? 0) {
                match = imagesAreIdentical(ids.map { variants[$0] ?? [] }, in: paths)
            } else {
                match = false
            }
            return Album(title: album, artist: artists[album] ?? "", trackCount: trackCounts[album] ?? 0,
                         declared: entry.sum, imageIDs: ids, imagesMatch: match)
        }.sorted { $0.title < $1.title }
    }

    /// Brings coverage in line with the track count where this can be done
    /// unambiguously. Works both ways: an album that gained tracks has too
    /// little coverage, and an album that lost tracks has too much.
    public static func repairing(
        _ artworkDB: Data, library: ITLibrary, paths: IPodPaths? = nil
    ) throws -> (data: Data, repaired: [Album]) {
        let albums = try audit(library: library, artworkDB: artworkDB, paths: paths)
        let current = Dictionary(try ArtworkDBEditor.trackCounts(in: artworkDB).map { ($0.imageID, $0.trackCount) },
                                 uniquingKeysWith: { first, _ in first })

        var counts: [UInt32: UInt32] = [:]
        var repaired: [Album] = []
        for album in albums {
            guard let patch = album.repairedCounts(current: current) else { continue }
            counts.merge(patch) { _, new in new }
            repaired.append(album)
        }
        guard !counts.isEmpty else { return (artworkDB, []) }
        return (try ArtworkDBEditor.settingTrackCounts(counts, in: artworkDB), repaired)
    }

    /// Compares the largest variant of each image. Reads only those slices,
    /// not whole `.ithmb` files - those can be tens of megabytes.
    private static func imagesAreIdentical(_ variantSets: [[ArtworkVariant]], in paths: IPodPaths) -> Bool {
        guard variantSets.count > 1, !variantSets.contains(where: \.isEmpty) else { return false }
        let references = variantSets.map { $0.max { $0.byteCount < $1.byteCount }! }
        guard let first = references.first,
              references.allSatisfy({ $0.byteCount == first.byteCount && $0.correlationID == first.correlationID })
        else { return false }

        var reference: Data?
        for variant in references {
            guard let bytes = slot(variant, in: paths) else { return false }
            if let reference { if bytes != reference { return false } } else { reference = bytes }
        }
        return reference != nil
    }

    private static func slot(_ variant: ArtworkVariant, in paths: IPodPaths) -> Data? {
        guard variant.hasSaneSlotSize, let url = try? variant.url(in: paths),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(variant.byteOffset))) != nil,
              let data = try? handle.read(upToCount: Int(variant.byteCount)),
              data.count == Int(variant.byteCount)
        else { return nil }
        return data
    }
}
