import Foundation

/// First artwork for an album that has none: new slots at the end of the
/// `.ithmb` files, a new `mhii` in `ArtworkDB`, and a pointer in `mhia` (on the
/// `iTunesDB` side, see `ITLibrary.linkingAlbumArtwork`).
///
/// Order on the device: pixels -> `ArtworkDB` -> only then the database.
/// Stopping after the pixels leaves unused slots (harmless); stopping after
/// `ArtworkDB` leaves an image nobody points to (also harmless). A database
/// pointing to an image that does not exist is what we avoid.
public enum ArtworkAddition {

    public struct Outcome: Sendable {
        public let imageID: UInt32
        public let slotOffsets: [UInt32: UInt32]
        /// Whether this write created `ArtworkDB` (the iPod had no artwork yet).
        public let createdDatabase: Bool
    }

    /// Appends an image. `render` provides pixels for every format in `mhlf`.
    ///
    /// - Parameters:
    ///   - deviceFormats: formats from the firmware description (`DeviceDescription.albumArt`).
    ///     Without `ArtworkDB` they are the only source of formats; with an existing
    ///     file they serve as a check - dimensions from the file and the device must match.
    ///   - allowingUnverifiedFormats: hardware trial of a format outside
    ///     `ConfirmedModels.artworkFormats`. Allows only a format that the device itself
    ///     describes as RGB565 little-endian.
    public static func add(
        ownerPersistentID: UInt64, sourceByteCount: UInt32, trackCount: UInt32,
        in paths: IPodPaths, deviceFormats: [DeviceDescription.ImageFormat] = [],
        allowingUnverifiedFormats: Bool = false,
        render: (_ width: Int, _ height: Int) throws -> ITHMBImage
    ) throws -> Outcome {
        let manager = FileManager.default
        let dbURL = paths.artworkDB
        let creating = !manager.fileExists(atPath: dbURL.path)
        let data: Data
        if creating {
            // Finder does not create ArtworkDB on the nano 2G. Only the device
            // itself can provide the formats then - we do not take them from the model table.
            guard !deviceFormats.isEmpty else {
                throw ITDBError.writeRefused(.unsupportedArtwork("no ArtworkDB, and the firmware listed no cover formats"))
            }
            let formats = deviceFormats.compactMap(ArtworkDBBuilder.Format.init)
            guard formats.count == deviceFormats.count else {
                let other = deviceFormats.filter { !$0.isLittleEndianRGB565 }.map { "\($0.formatID) \($0.pixelFormat)" }
                throw ITDBError.writeRefused(.unsupportedArtwork("encoding \(other.joined(separator: ", "))"))
            }
            data = ArtworkDBBuilder.empty(formats: formats, identity: ArtworkDBBuilder.randomIdentity())
        } else {
            data = try Data(contentsOf: dbURL)
        }
        let artwork = try ArtworkDBParser.parse(data)
        let template = artwork.images.first

        // Dimensions: from the template (mhif does not carry them), and without a
        // template from the device description. When both sources exist, they must match.
        let described = Dictionary(deviceFormats.map { ($0.formatID, $0) }, uniquingKeysWith: { first, _ in first })
        var sizes: [UInt32: (width: Int, height: Int)] = [:]
        for variant in template?.variants ?? [] { sizes[variant.correlationID] = (Int(variant.width), Int(variant.height)) }
        for format in artwork.formats {
            let id = format.correlationID
            if let stated = described[id] {
                guard stated.isLittleEndianRGB565 else {
                    throw ITDBError.writeRefused(.unsupportedArtwork("format \(id) in \(stated.pixelFormat), not RGB565 LE"))
                }
                if let known = sizes[id], known.width != stated.width || known.height != stated.height {
                    throw ITDBError.writeRefused(.unsupportedArtwork("format \(id): ArtworkDB says \(known.width)x\(known.height), the firmware \(stated.width)x\(stated.height)"))
                }
                sizes[id] = sizes[id] ?? (stated.width, stated.height)
            }
            guard let size = sizes[id] else {
                throw ITDBError.writeRefused(.unsupportedArtwork("format \(id) has no known size"))
            }
            // Without a template we build the record ourselves, so our slot must be the one in the file.
            if template == nil {
                let built = ArtworkDBBuilder.Format(formatID: id, width: size.width, height: size.height).slotSize
                guard built == Int(format.slotSize) else {
                    throw ITDBError.writeRefused(.unsupportedArtwork("format \(id): a \(format.slotSize)-byte slot in ArtworkDB, \(built) bytes from its size"))
                }
            }
        }
        // Wrongly encoded pixels are garbage on the iPod screen, not an error
        // anyone notices before the write - hence a refusal, not an attempt.
        let unconfirmed = artwork.formats.map(\.correlationID).filter { !ConfirmedModels.artworkFormats.contains($0) }
        if !unconfirmed.isEmpty {
            guard allowingUnverifiedFormats else {
                throw ITDBError.writeRefused(.unsupportedArtwork("cover formats \(unconfirmed.sorted()) aren't measured on a device yet"))
            }
            let undescribed = unconfirmed.filter { described[$0]?.isLittleEndianRGB565 != true }
            guard undescribed.isEmpty else {
                throw ITDBError.writeRefused(.unsupportedArtwork("formats \(undescribed.sorted()) aren't described by the device as RGB565 LE"))
            }
        }

        // 1. Pixels at the end of every file. An error rolls back by truncating to
        //    the previous length, and removes files and folders created here.
        let createdDirectory = !manager.fileExists(atPath: paths.artworkDirectory.path)
        var offsets: [UInt32: UInt32] = [:]
        var appended: [(URL, UInt64)] = []
        var createdFiles: [URL] = []
        func undoPixels() {
            for (url, length) in appended where !createdFiles.contains(url) {
                if let handle = try? FileHandle(forUpdating: url) { try? handle.truncate(atOffset: length); try? handle.close() }
            }
            for url in createdFiles { try? manager.removeItem(at: url) }
            if createdDirectory { try? manager.removeItem(at: paths.artworkDirectory) }
        }
        do {
            if createdDirectory { try manager.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true) }
            for format in artwork.formats {
                // The name is ours, but the file under it may be a link pointing outside.
                guard let url = paths.artworkFile("F\(format.correlationID)_1.ithmb") else {
                    throw ITDBError.unsafePath("F\(format.correlationID)_1.ithmb")
                }
                if !manager.fileExists(atPath: url.path) {
                    guard manager.createFile(atPath: url.path, contents: Data()) else {
                        throw ITDBError.writeRefused(.inconsistent("can't create \(url.lastPathComponent)"))
                    }
                    createdFiles.append(url)
                }
                let handle = try FileHandle(forUpdating: url)
                defer { try? handle.close() }
                let end = try handle.seekToEnd()
                guard end % UInt64(format.slotSize) == 0 else {
                    throw ITDBError.writeRefused(.inconsistent("\(url.lastPathComponent) has \(end) bytes, not a multiple of the \(format.slotSize)-byte slot"))
                }
                guard end + UInt64(format.slotSize) < 0xFFFF_FFFF else {
                    throw ITDBError.writeRefused(.inconsistent("\(url.lastPathComponent) would pass 4 GB"))
                }
                let (w, h) = sizes[format.correlationID]!
                let image = try render(w, h)
                guard image.width == w, image.height == h else {
                    throw ITDBError.writeRefused(.inconsistent("rendered \(image.width)x\(image.height), the format wants \(w)x\(h)"))
                }
                let stride = Int(format.slotSize) / (2 * h)
                let bytes = ITHMB.encodeRGB565(image, pixelStride: stride, slotSize: Int(format.slotSize))
                try handle.write(contentsOf: Data(bytes))
                try handle.synchronize()
                appended.append((url, end))
                offsets[format.correlationID] = UInt32(end)
            }
        } catch {
            undoPixels()
            throw error
        }

        // 2. ArtworkDB: a new record - from a template or, when there are no images
        //    yet, built from scratch. Written through a temporary file and a swap.
        let temp = dbURL.deletingLastPathComponent().appendingPathComponent("ArtworkDB.clickwill-\(UUID().uuidString.prefix(8))")
        do {
            let result: ArtworkDBEditor.Result
            if let template {
                result = try ArtworkDBEditor.addingImage(
                    to: data, template: template.id,
                    image: .init(trackPersistentID: ownerPersistentID, sourceByteCount: sourceByteCount,
                                 trackCount: trackCount, slotOffsets: offsets))
            } else {
                let variants = artwork.formats.map { format in
                    let size = sizes[format.correlationID]!
                    return (format: ArtworkDBBuilder.Format(formatID: format.correlationID, width: size.width, height: size.height),
                            offset: offsets[format.correlationID]!)
                }
                let record = ArtworkDBBuilder.imageRecord(
                    ownerPersistentID: ownerPersistentID, sourceByteCount: sourceByteCount,
                    trackCount: trackCount, variants: variants)
                result = try ArtworkDBEditor.insertingImage(record, into: data)
            }
            _ = try ArtworkDBParser.parse(result.data)   // must parse before it reaches the device
            try result.data.write(to: temp, options: .atomic)
            if creating {
                try manager.moveItem(at: temp, to: dbURL)
            } else {
                _ = try manager.replaceItemAt(dbURL, withItemAt: temp)
            }
            return Outcome(imageID: result.imageID, slotOffsets: offsets, createdDatabase: creating)
        } catch {
            try? manager.removeItem(at: temp)
            undoPixels()
            throw error
        }
    }
}

extension ArtworkAddition {

    /// The same image for more tracks: a new `mhii` for every track that does
    /// not have it yet, with the same `.ithmb` slots as `imageID`.
    /// No pixels are written a second time - only `ArtworkDB` changes.
    ///
    /// Why: the nano 2G (firmware 1.1.3) looks up artwork during playback
    /// by the track's `persistentID` (`mhii` 0x14), not by `mhit` 0x160.
    /// One record per album showed the artwork only for the owner track
    /// ("One Of Those Days"); the other 12 tracks had none.
    ///
    /// - Returns: track `persistentID` -> identifier of its new `mhii`.
    public static func sharing(imageID: UInt32, withTracks tracks: [UInt64], in paths: IPodPaths) throws -> [UInt64: UInt32] {
        let dbURL = paths.artworkDB
        var data = try Data(contentsOf: dbURL)
        let artwork = try ArtworkDBParser.parse(data)
        guard let image = artwork.images.first(where: { $0.id == imageID }) else {
            throw ITDBError.writeRefused(.inconsistent("ArtworkDB has no image \(imageID)"))
        }
        guard let sourceByteCount = image.rawHeader[MhiiLayout.sourceByteCount] else {
            throw ITDBError.writeRefused(.inconsistent("image record \(imageID) has a short header"))
        }
        let slots = Dictionary(image.variants.map { ($0.correlationID, $0.byteOffset) }, uniquingKeysWith: { first, _ in first })
        var owned = Set(artwork.images.map(\.trackPersistentID))
        var created: [UInt64: UInt32] = [:]
        for track in tracks where !owned.contains(track) {
            let result = try ArtworkDBEditor.addingImage(
                to: data, template: imageID,
                image: .init(trackPersistentID: track, sourceByteCount: sourceByteCount, trackCount: 1, slotOffsets: slots))
            data = result.data
            created[track] = result.imageID
            owned.insert(track)
        }
        guard !created.isEmpty else { return [:] }
        _ = try ArtworkDBParser.parse(data)   // must parse before it reaches the device
        let temp = dbURL.deletingLastPathComponent().appendingPathComponent("ArtworkDB.clickwill-\(UUID().uuidString.prefix(8))")
        do {
            try data.write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(dbURL, withItemAt: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        return created
    }
}

extension ITLibrary {
    /// Sets the artwork owner track in the album record (`mhia`).
    /// The album is found by title and artist as in `mhia`; no record = no change.
    public func linkingAlbumArtwork(album title: String, ownerPersistentID: UInt64) -> ITLibrary {
        var copy = self
        copy.sections = sections.map { section in
            guard case .albums(let albums) = section.content else { return section }
            var updated = section
            updated.content = .albums(albums.map { album in
                guard album.title == title else { return album }
                var changed = album
                changed.artworkOwnerPersistentID = ownerPersistentID
                return changed
            })
            return updated
        }
        return copy
    }
}
