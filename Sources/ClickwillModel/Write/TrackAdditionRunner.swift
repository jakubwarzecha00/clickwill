import Foundation
import CoreGraphics
import ImageIO
import ITDBKit

/// Carrying out the add queue: conversion if needed, copying the file to
/// the device, hooking it into the database, a new album's artwork.
///
/// The order is such that at no moment is there an entry pointing to an empty
/// place: the file is copied before the database, and the artwork is added after the tracks are hooked in
/// (because only then does the record `mhia` must point to exist), but before
/// the database write (because the database must already point to finished images).
public enum TrackAdditionRunner {

    /// What the device's `WritePolicy` allows when adding.
    public struct AdditionRules: Sendable {
        public var crossKindTemplates = true
        public var unverifiedArtworkFormats = false

        public init() {}

        public init(for device: IPodDevice) {
            crossKindTemplates = !device.writesOutsideConfirmedModels || device.writePolicy == .developer
            unverifiedArtworkFormats = device.writePolicy == .developer
        }
    }

    public struct Outcome: Sendable {
        public var library: ITLibrary
        /// Files copied to the device - to clean up if the database write fails.
        public var copied: [URL] = []
        public var done: [UUID] = []
        /// Tracks that were not added.
        public var failed: [WriteProblem] = []
        /// New albums added without artwork.
        public var coversFailed: [WriteProblem] = []
        public var covers: Int = 0
        public var coverImages: [UInt64: CGImage] = [:]
        /// The identifier given in the database to each added track - needed
        /// to place it in the album where it was dropped.
        public var uniqueIDs: [UUID: UInt32] = [:]
        /// Stopped, because the same volume is no longer at the iPod's path.
        /// The database is then not written, and cleaning up is possible only after confirming
        /// again that it is still this iPod.
        public var aborted = false
    }

    /// - Parameters:
    ///   - artworkFormats: artwork formats from the firmware description - needed when
    ///     the iPod has no `ArtworkDB` yet.
    ///   - rules: on an unconfirmed model only a template of the same kind; in developer
    ///     mode also artwork formats that aren't measured yet (`ArtworkAddition`).
    ///   - ensureMounted: called before every file and before the artwork; an error
    ///     stops the whole queue (`IPodVolume.ensureStillMounted`).
    ///   - progress: one line per track, to show as it goes.
    public static func run(_ additions: [PendingAddition], into library: ITLibrary, paths: IPodPaths,
                           artworkFormats: [DeviceDescription.ImageFormat] = [],
                           rules: AdditionRules = AdditionRules(),
                           ensureMounted: @Sendable () throws -> Void = {},
                           progress: (@Sendable (String) -> Void)? = nil) async -> Outcome {
        var outcome = Outcome(library: library)

        // Artwork is added only to albums that do not exist yet - for an existing one
        // we do not replace it when adding a song, because nobody asked for that.
        let existingAlbums = Set(library.albums.map { AlbumKey(album: $0.title ?? "", albumArtist: $0.artist ?? "") })
        var coverOwner: [AlbumKey: (id: UInt64, source: AudioImport.CoverSource, tracks: Int)] = [:]

        for (index, addition) in additions.enumerated() {
            progress?("[\(index + 1)/\(additions.count)] \(addition.draft.title)"
                      + (addition.target.map { " - converting to \($0.label)" } ?? ""))
            do {
                var draft = addition.draft
                var source = addition.source
                var temporary: URL?
                if let target = addition.target {
                    let converted = try await AudioFiles.convert(source, to: target)
                    temporary = converted
                    source = converted
                    guard let after = await AudioFiles.stream(at: converted),
                          AudioCompatibility.verdict(for: after).isSupported else {
                        try? FileManager.default.removeItem(at: converted)
                        outcome.failed.append(WriteProblem(draft.title, .stillNotPlayable))
                        continue
                    }
                    draft.kind = target.kindForDevice
                    draft.bitRate = UInt32(after.bitRate / 1000)
                    draft.sampleRate = UInt32(after.sampleRate)
                }
                do {
                    try ensureMounted()
                } catch {
                    if let temporary { try? FileManager.default.removeItem(at: temporary) }
                    outcome.aborted = true
                    return outcome
                }
                let placement = try FileReplacement.place(source, in: paths)
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                outcome.copied.append(placement.url)
                draft.relativePath = placement.relativePath
                draft.sizeBytes = placement.sizeBytes

                // The identifier is drawn here, so we know which track
                // the new album's artwork should point to.
                let persistentID = UInt64.random(in: 1...UInt64.max)
                outcome.library = try outcome.library.addingTracks([draft], crossKindTemplates: rules.crossKindTemplates,
                                                                   persistentID: { persistentID })
                outcome.done.append(addition.id)
                // Adding appends the record at the end of the track list.
                if let added = outcome.library.tracks.last, added.persistentID == persistentID {
                    outcome.uniqueIDs[addition.id] = added.uniqueID
                }

                let key = draft.albumKey
                if let cover = addition.cover, !existingAlbums.contains(key) {
                    if var owner = coverOwner[key] {
                        owner.tracks += 1
                        coverOwner[key] = owner
                    } else {
                        coverOwner[key] = (persistentID, cover, 1)
                    }
                }
            } catch {
                outcome.failed.append(WriteProblem(addition.draft.title, .error(error)))
            }
        }

        if !coverOwner.isEmpty {
            do { try ensureMounted() } catch {
                outcome.aborted = true
                return outcome
            }
        }
        for (key, owner) in coverOwner {
            do {
                let (image, byteCount) = try TrackAdditionRunner.coverImage(from: owner.source)
                _ = try ArtworkAddition.add(ownerPersistentID: owner.id, sourceByteCount: byteCount,
                                            trackCount: UInt32(owner.tracks), in: paths,
                                            deviceFormats: artworkFormats,
                                            allowingUnverifiedFormats: rules.unverifiedArtworkFormats) { width, height in
                    try ITHMBImage(rendering: image, width: width, height: height)
                }
                outcome.library = outcome.library
                    .linkingAlbumArtwork(album: key.album, ownerPersistentID: owner.id)
                    // Each track of the album must know by itself that it has artwork -
                    // coverage in ArtworkDB does not take care of that.
                    .markingAlbumArtwork(album: key.album, sourceByteCount: byteCount)
                outcome.coverImages[owner.id] = image
                outcome.covers += 1
            } catch {
                outcome.coversFailed.append(WriteProblem(key.album, .error(error)))
            }
        }
        return outcome
    }

    /// The image and source size for `mhii` 0x30 (image + artwork count, as Apple does).
    public static func coverImage(from source: AudioImport.CoverSource) throws -> (image: CGImage, byteCount: UInt32) {
        switch source {
        case .file(let url):
            guard let cgSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(cgSource, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { throw ArtworkError.unreadableImage(url) }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            return (image, ITTrack.imageSourceByteCount(pictureBytes: UInt32(clamping: bytes)))
        case .embedded(let data):
            guard let provider = CGDataProvider(data: data as CFData),
                  let source = CGImageSourceCreateWithDataProvider(provider, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw ArtworkError.unreadableImage(URL(fileURLWithPath: "tags")) }
            return (image, ITTrack.imageSourceByteCount(pictureBytes: UInt32(clamping: data.count)))
        }
    }
}
