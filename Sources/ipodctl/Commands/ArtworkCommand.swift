import Foundation
import ImageIO
import ITDBKit
import ClickwillModel

/// `artwork` - artwork on the iPod. Modes, each in its own function:
///
/// - `artwork [--extract ID --out FILE.png]` - a summary or extracting one image;
/// - `artwork --check-counts [--apply]` - albums whose artwork the app sees but the iPod does not;
/// - `artwork --add ALBUM --file IMAGE [--unverified-formats] [--apply]` - an album's first artwork;
/// - `artwork --per-track ALBUM [--apply]` - album artwork in a separate mhii for each track.
///
/// Writes go through the transaction as in the app window (`DeviceLibrary.write`).
enum ArtworkCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        if call.has("--check-counts") { return try await checkCounts(on: device, call) }
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let existingArtwork = try device.readArtwork()
        if let albumName = call.value(for: "--per-track") {
            return try await addPerTrack(album: albumName, on: onDevice, artwork: existingArtwork)
        }
        if let albumName = call.value(for: "--add") {
            return try await addFirst(album: albumName, on: onDevice, artwork: existingArtwork)
        }
        guard let artwork = existingArtwork else {
            print("The device has no ArtworkDB file.")
            return
        }
        if let raw = call.value(for: "--extract") {
            return try extract(raw, from: device, library: library, artwork: artwork, to: call.value(for: "--out") ?? "cover.png")
        }
        summarize(library: library, artwork: artwork)
    }

    /// The image record declares fewer tracks than the album has - the app sees
    /// the artwork, the iPod does not. With `--apply` it fixes albums with one image - that
    /// is a repair the transaction makes on every write, so writing the
    /// library unchanged is enough.
    private static func checkCounts(on device: IPodDevice, _ call: Invocation) async throws {
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let data = try Data(contentsOf: device.paths.artworkDB)
        let albums = try ArtworkCoverage.audit(library: library, artworkDB: data, paths: device.paths)
        let broken = albums.filter { !$0.isComplete }

        report("Artwork coverage", [
            ("albums with an image", "\(albums.count)"),
            ("with mismatched coverage", "\(broken.count)"),
        ])
        for album in broken {
            let name = album.title.isEmpty ? "(untitled)" : album.title
            print("  \(name): the image covers \(album.declared) of \(album.trackCount) tracks"
                + "  [mhii \(album.imageIDs.map(String.init).joined(separator: ", "))]"
                + (album.isRepairable ? "" : "  - different images, left alone"))
        }
        let fixable = broken.filter(\.isRepairable)
        guard !fixable.isEmpty else { return }
        print("\nTo repair (one image per album): \(fixable.count)")
        guard call.has("--apply") else { print("  That was a preview. To write: add --apply"); return }

        let outcome = try await onDevice.write(library, note: "ipodctl artwork --check-counts")
        announce(outcome)
        print("  Albums with corrected coverage: \(outcome.repairs.coverage.count)")
    }

    /// Album artwork in the mhii of each track, the same slots, without new pixels.
    /// The nano 2G looks up the image by the track's persistentID - one record per album
    /// works only for the owner track.
    private static func addPerTrack(album albumName: String, on onDevice: DeviceLibrary,
                                    artwork existingArtwork: ArtworkLibrary?) async throws {
        let (device, library) = (onDevice.device, onDevice.library)
        let tracks = library.tracks.filter { $0.album == albumName }
        guard !tracks.isEmpty else { throw CommandError("there is no album '\(albumName)'") }
        guard let artwork = existingArtwork else { throw CommandError("the iPod has no ArtworkDB - run artwork --add first") }
        let byTrack = artwork.indexedByTrack()
        let images = Set(tracks.compactMap { byTrack[$0.persistentID]?.id })
        guard images.count == 1, let imageID = images.first else {
            throw CommandError(images.isEmpty ? "the album has no artwork - run artwork --add first"
                                : "the album has several different images \(images.sorted()) - left alone")
        }
        let missing = tracks.filter { byTrack[$0.persistentID] == nil }
        report("Artwork on every track", [
            ("iPod", "\(device.volume.name) - \(device.model.name)"),
            ("album", albumName),
            ("image", "mhii \(imageID)"),
            ("tracks", "\(tracks.count), with their own mhii \(tracks.count - missing.count)"),
            ("to add", missing.isEmpty ? "nothing" : "\(missing.count) mhii, the same slots, no new pixels"),
            ("writing", device.supportsWriting ? "allowed" : "BLOCKED: \(device.readOnlyReason?.description ?? "?")"),
        ])
        guard !missing.isEmpty else { return }
        guard onDevice.call.has("--apply") else { print("\n  That was a preview. To write: add --apply"); return }
        var changes = ChangeSet()
        changes.queueCoverSharing(imageID: imageID, with: missing, album: albumName, for: AlbumID(albumOf: tracks))
        print("")
        announce(try await onDevice.write(library, changes: changes, note: "ipodctl artwork --per-track \(albumName)"))
    }

    /// The first artwork for an album without artwork: a new mhii, slots and the pointer in mhia.
    /// Without ArtworkDB it creates one from the formats the firmware gives;
    /// `--unverified-formats` is a hardware trial of a format outside the confirmed ones.
    private static func addFirst(album albumName: String, on onDevice: DeviceLibrary,
                                 artwork existingArtwork: ArtworkLibrary?) async throws {
        let (device, library) = (onDevice.device, onDevice.library)
        guard let file = onDevice.call.value(for: "--file") else { throw CommandError("--add needs --file IMAGE") }
        let tracks = library.tracks.filter { $0.album == albumName }
        guard let owner = tracks.first else { throw CommandError("there is no album '\(albumName)'") }
        let byTrack = existingArtwork?.indexedByTrack() ?? [:]
        if let existing = tracks.first(where: { byTrack[$0.persistentID] != nil }) {
            throw CommandError("the album already has artwork (mhii on '\(existing.title ?? "?")') - this command is for albums without artwork")
        }
        let url = URL(fileURLWithPath: file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CommandError("cannot load the image \(file)") }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let albumRecord = library.albums.first { $0.title == albumName }
        let deviceFormats = device.firmwareDescription?.albumArt ?? []
        let formats = existingArtwork.map { $0.formats.map { "\($0.correlationID)" }.joined(separator: ", ") }
            ?? deviceFormats.map { "\($0.formatID) \($0.width)x\($0.height) \($0.pixelFormat)" }.joined(separator: ", ")
        report("First artwork", [
            ("iPod", "\(device.volume.name) - \(device.model.name), database \(device.format.name)"),
            ("album", albumName),
            ("tracks", "\(tracks.count)"),
            ("owner (mhii)", "\(owner.title ?? "?") [dbid \(String(owner.persistentID, radix: 16))]"),
            ("mhia points to today", albumRecord.map { String($0.artworkOwnerPersistentID, radix: 16) } ?? "no mhia record"),
            ("image", "\(cg.width)x\(cg.height), \(fileSize) B"),
            ("ArtworkDB", existingArtwork.map { "\($0.images.count) images" } ?? "none - will be created from the firmware formats"),
            ("formats", formats.isEmpty ? "none" : formats),
            ("writing", device.supportsWriting ? "allowed" : "BLOCKED: \(device.readOnlyReason?.description ?? "?")"),
        ])
        guard onDevice.call.has("--apply") else { print("\n  That was a preview. To write: add --apply"); return }
        // The image lands on the iPod before the database, and the 0x160 pointer in the album's
        // tracks is added by the repair during the write - as in the app.
        var changes = ChangeSet()
        changes.queueFirstCover(cg, sourceByteCount: ITTrack.imageSourceByteCount(pictureBytes: UInt32(clamping: fileSize)),
                                owner: owner, tracks: tracks, album: albumName, for: AlbumID(albumOf: tracks),
                                allowingUnverifiedFormats: onDevice.call.has("--unverified-formats"))
        print("")
        announce(try await onDevice.write(library, changes: changes, note: "ipodctl artwork --add \(albumName)"))
    }

    /// The largest artwork variant of track `--extract ID` to a PNG file (`--out`, cover.png by default).
    private static func extract(_ raw: String, from device: IPodDevice, library: ITLibrary, artwork: ArtworkLibrary,
                                to path: String) throws {
        guard let wanted = UInt32(raw) else { throw CommandError("the track identifier must be a number") }
        guard let track = library.tracks.first(where: { $0.uniqueID == wanted }) else {
            throw CommandError("there is no track with identifier \(wanted)")
        }
        guard let image = artwork.image(forTrackPersistentID: track.persistentID),
              let variant = image.largest
        else { throw CommandError("track \(wanted) has no artwork") }

        let decoded = try ITHMB.read(variant, in: device.paths)
        try writePNG(decoded, to: path)
        print("\(track.artist ?? "?") - \(track.title ?? "?")")
        print("  \(variant.plainFileName) offset \(variant.byteOffset), \(decoded.width)x\(decoded.height) -> \(path)")
    }

    private static func summarize(library: ITLibrary, artwork: ArtworkLibrary) {
        let byPersistentID = Dictionary(
            library.tracks.map { ($0.persistentID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        let linked = artwork.images.compactMap { byPersistentID[$0.trackPersistentID] }
        let coveredAlbums = Set(linked.map(\.albumKey))
        let allAlbums = Set(library.tracks.map(\.albumKey))
        let embedded = library.tracks.count { $0.hasEmbeddedArtwork }
        report("Artwork", [
            ("images in ArtworkDB", "\(artwork.images.count)"),
            ("orphaned", "\(artwork.images.count - linked.count)"),
            ("albums with a thumbnail", "\(coveredAlbums.count) of \(allAlbums.count)"),
            ("tracks with artwork in the file", "\(embedded) of \(library.tracks.count)"),
        ])
        let uncovered = allAlbums.subtracting(coveredAlbums)
        if !uncovered.isEmpty {
            print("\nAlbums without a thumbnail in ArtworkDB")
            for key in uncovered.sorted(by: { ($0.albumArtist, $0.album) < ($1.albumArtist, $1.album) }).prefix(10) {
                print("  \(key.album) / \(key.albumArtist)")
            }
            if uncovered.count > 10 { print("  ... and \(uncovered.count - 10) more") }
        }
        print("\nFormats")
        for format in artwork.formats.sorted(by: { $0.correlationID < $1.correlationID }) {
            let sample = artwork.images.compactMap { $0.variant(correlationID: format.correlationID) }.first
            let dimensions = sample.map { "\($0.width)x\($0.height), row stride \($0.pixelStride) px" } ?? "?"
            print("  F\(format.correlationID)_1.ithmb  slot \(format.slotSize) B  \(dimensions)")
        }
        print("\nExamples")
        for image in artwork.images.prefix(5) {
            let track = byPersistentID[image.trackPersistentID]
            let name = track.map { "\($0.artist ?? "?") - \($0.album ?? "?")" } ?? "(no track)"
            print("  id=\(image.id)  \(image.variants.count) variants  \(name)")
        }
    }

    /// Writing a PNG through ImageIO - only for the CLI, the core stays without graphics dependencies.
    private static func writePNG(_ image: ITHMBImage, to path: String) throws {
        guard let cgImage = image.makeCGImage() else { throw CommandError("could not build the image") }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            throw CommandError("could not create the file \(path)")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw CommandError("could not write \(path)") }
    }
}
