import Foundation
import ITDBKit

/// The state of artwork on the iPod - the same checks the write performs as
/// repairs (`LibraryModel.apply`), here only counted, without changing anything.
///
/// Why: a report of "the artwork did not save" has several separate causes,
/// each measured on the device:
/// a missing image, `mhii` 0x38 coverage, the 0x7E marker, the 0x7C/0x80 source size,
/// the 0x160 pointer, the second identifier at 0xA8, the album record identity
/// and finally the image data in the `.ithmb` files. The report says which of them
/// occurs - without titles, unless the user points to an album themselves.
public struct ArtworkHealth: Sendable {

    public enum Check: String, CaseIterable, Sendable {
        case noCover = "no cover image"
        case coverage = "cover counts fewer or more songs than the album has (mhii 0x38)"
        case marker = "artwork marker missing (mhit 0x7E)"
        case source = "song points at an image size that isn't in ArtworkDB (mhit 0x7C/0x80)"
        case identifier = "song points at an image that doesn't exist (mhit 0x160)"
        case secondaryID = "second track identifier missing (mhit 0xA8)"
        case albumIdentity = "album record reuses a track identifier"
        case imageData = "image data missing or cut short in .ithmb"
    }

    /// For each check: album -> how many tracks (or images) it affects.
    public let findings: [Check: [String: Int]]
    /// How many image variants there are in each format (e.g. 1055: 144).
    public let variantsPerFormat: [UInt32: Int]
    public let imageCount: Int
    public let albumCount: Int

    public static func check(library: ITLibrary, artwork: ArtworkLibrary?, artworkDB: Data?, paths: IPodPaths?,
                             files: any FileSystem = LocalFileSystem()) -> ArtworkHealth {
        var findings: [Check: [String: Int]] = [:]
        var tracksPerAlbum: [String: Int] = [:]
        var albumOfTrack: [UInt64: String] = [:]
        for track in library.tracks {
            tracksPerAlbum[track.album ?? "", default: 0] += 1
            albumOfTrack[track.persistentID] = track.album ?? ""
        }

        var markers: [String: Int] = [:]
        for track in library.tracks where !track.hasArtworkMarker { markers[track.album ?? "", default: 0] += 1 }
        findings[.marker] = markers
        findings[.secondaryID] = library.repairingSecondaryIdentifiers().repaired
        findings[.albumIdentity] = Dictionary(library.repairingAlbumIdentities().repaired.map { ($0, 1) },
                                              uniquingKeysWith: +)

        var perFormat: [UInt32: Int] = [:]
        if let artwork {
            let identifiers = artwork.imageIdentifiersByAlbum(in: library)
            findings[.noCover] = tracksPerAlbum.filter { identifiers[$0.key] == nil }
            findings[.source] = library.repairingArtworkSources(imageSourcesByAlbum: artwork.imageSourcesByAlbum(in: library)).repaired
            findings[.identifier] = library.repairingArtworkIdentifiers(
                imageIdentifiersByAlbum: identifiers, existingIdentifiers: artwork.imageIdentifiers).repaired

            var brokenData: [String: Int] = [:]
            var fileSizes: [String: Int64] = [:]
            for image in artwork.images {
                for variant in image.variants {
                    perFormat[variant.correlationID, default: 0] += 1
                    guard let paths else { continue }
                    guard let url = try? variant.url(in: paths), variant.hasSaneBounds else {
                        brokenData[albumOfTrack[image.trackPersistentID] ?? "", default: 0] += 1
                        continue
                    }
                    let size = fileSizes[url.path] ?? {
                        let value = files.size(of: url) ?? -1
                        fileSizes[url.path] = value
                        return value
                    }()
                    if size < Int64(variant.byteOffset) + Int64(variant.byteCount) {
                        brokenData[albumOfTrack[image.trackPersistentID] ?? "", default: 0] += 1
                    }
                }
            }
            findings[.imageData] = brokenData
        } else {
            findings[.noCover] = tracksPerAlbum
        }

        if let artworkDB, let audit = try? ArtworkCoverage.audit(library: library, artworkDB: artworkDB) {
            findings[.coverage] = Dictionary(audit.filter { $0.declared != $0.trackCount }.map { ($0.title, $0.trackCount) },
                                             uniquingKeysWith: +)
        }

        return ArtworkHealth(findings: findings.filter { !$0.value.isEmpty }, variantsPerFormat: perFormat,
                             imageCount: artwork?.images.count ?? 0, albumCount: tracksPerAlbum.count)
    }

    /// Report lines without titles: how many albums each check affects.
    public var summary: [String] {
        var lines = ["Artwork: \(imageCount) images, formats "
            + (variantsPerFormat.isEmpty ? "none" : variantsPerFormat.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))]
        let problems = Check.allCases.compactMap { check -> String? in
            guard let albums = findings[check] else { return nil }
            return "  \(check.rawValue): \(albums.count) of \(albumCount) album titles"
        }
        lines += problems.isEmpty ? ["  no artwork problems found"] : problems
        return lines
    }

    /// Details of one album - only when the user pointed to it themselves.
    public func details(forAlbum title: String) -> [String] {
        let problems = Check.allCases.compactMap { check -> String? in
            findings[check]?[title].map { "  \(check.rawValue): \($0)" }
        }
        return problems.isEmpty ? ["  no artwork problems found for this album"] : problems
    }
}
