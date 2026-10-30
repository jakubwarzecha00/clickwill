import Foundation
import ITDBKit

/// How the library looks in Rockbox. Rockbox reads the tags inside each song file, not
/// iTunesDB, so an edit made only in the iPod's library, artwork only in ArtworkDB or a
/// compilation flag don't reach it (`RockboxInstallation`, `RockboxImage`).
///
/// Read-only: nothing is written to the files. Only albums with an issue are listed.
public struct RockboxReport: Sendable {

    public enum Issue: Sendable, Hashable {
        /// The library has artwork for these songs, the files carry none.
        case artworkOnlyInLibrary(tracks: Int)
        /// The files carry an image Rockbox doesn't show.
        case artworkNotShown(RockboxImage, tracks: Int)
        /// A compilation without an album artist tag: Rockbox lists it under `<Untagged>`.
        case untaggedCompilation(tracks: Int)
        /// Fields whose file tag differs from the library (title, artist, album, album artist, track number).
        case tagsDiffer(fields: [String], tracks: Int)
        /// Files that couldn't be read.
        case unreadable(tracks: Int)

        /// Technical, for the report and the sheet.
        public var detail: String {
            switch self {
            case .artworkOnlyInLibrary(let tracks):
                "artwork in ArtworkDB only · no embedded image in \(tracks) files"
            case .artworkNotShown(let image, let tracks):
                "embedded \(Self.name(image)) in \(tracks) files · Rockbox decodes baseline JPEG only"
            case .untaggedCompilation(let tracks):
                "compilation flag ignored by Rockbox · no album artist tag in \(tracks) files · listed as <Untagged>"
            case .tagsDiffer(let fields, let tracks):
                "\(fields.joined(separator: ", ")) \(fields.count == 1 ? "differs" : "differ") between iTunesDB and file tags in \(tracks) files"
            case .unreadable(let tracks):
                "\(tracks) files unreadable"
            }
        }

        private static func name(_ image: RockboxImage) -> String {
            switch image {
            case .jpeg: "JPEG"
            case .progressiveJPEG: "progressive JPEG"
            case .unsupportedJPEG: "JPEG (unsupported coding)"
            case .png: "PNG"
            case .other: "image of unknown type"
            }
        }
    }

    public struct Album: Sendable, Identifiable {
        public var id: String { "\(artist ?? "")\u{1F}\(title ?? "")" }
        public let title: String?
        public let artist: String?
        public let issues: [Issue]

        public init(title: String?, artist: String?, issues: [Issue]) {
            self.title = title
            self.artist = artist
            self.issues = issues
        }
    }

    public let installation: RockboxInstallation
    public let albums: [Album]
    public let scannedTracks: Int

    /// For screenshots and tests; `build` reads the files.
    public init(installation: RockboxInstallation, albums: [Album], scannedTracks: Int) {
        self.installation = installation
        self.albums = albums
        self.scannedTracks = scannedTracks
    }

    /// What one file says, reduced to what the comparison needs.
    struct FileTags: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var albumArtist: String?
        var trackNumber: UInt32
        var image: RockboxImage?
    }

    /// Reads every song file of the library. `read` is the tag reader - `AudioImport` in the
    /// app, a stub in tests.
    ///
    /// Checked against Rockbox's own parser (`get_metadata`) on MP3 (ID3v2.3, 2.4),
    /// AAC, ALAC and FLAC files: the same fields, and the same embedded image sizes to the byte.
    /// AVFoundation doesn't return FLAC pictures, but FLAC is never in iTunesDB.
    public static func build(library: ITLibrary, paths: IPodPaths, installation: RockboxInstallation,
                             progress: (@Sendable (Int, Int) -> Void)? = nil) async -> RockboxReport {
        await build(library: library, paths: paths, installation: installation, progress: progress) { url in
            guard let candidate = try? await AudioImport.candidate(at: url) else { return nil }
            let draft = candidate.draft
            return FileTags(title: draft.title, artist: draft.artist, album: draft.album, albumArtist: draft.albumArtist,
                            trackNumber: draft.trackNumber, image: candidate.artwork.map(RockboxImage.init))
        }
    }

    static func build(library: ITLibrary, paths: IPodPaths, installation: RockboxInstallation,
                      progress: (@Sendable (Int, Int) -> Void)?,
                      read: @Sendable (URL) async -> FileTags?) async -> RockboxReport {
        let groups = Dictionary(grouping: library.tracks) { AlbumKey(title: $0.album, artist: $0.albumArtist ?? $0.artist) }
        var albums: [Album] = []
        var scanned = 0
        let total = library.tracks.count
        for key in groups.keys.sorted(by: { ($0.artist ?? "", $0.title ?? "") < ($1.artist ?? "", $1.title ?? "") }) {
            var onlyInLibrary = 0, untagged = 0, unreadable = 0
            var notShown: [RockboxImage: Int] = [:]
            var differing: [String: Int] = [:]
            var tracksDiffering = 0
            for track in groups[key] ?? [] {
                scanned += 1
                progress?(scanned, total)
                guard let url = track.fileURL(on: paths), let tags = await read(url) else { unreadable += 1; continue }
                if let image = tags.image {
                    if !image.isShownByRockbox { notShown[image, default: 0] += 1 }
                } else if track.embeddedArtworkCount > 0 {
                    onlyInLibrary += 1
                }
                if track.isCompilation && (tags.albumArtist ?? "").isEmpty { untagged += 1 }
                let fields = differingFields(track, tags)
                if !fields.isEmpty { tracksDiffering += 1 }
                for field in fields { differing[field, default: 0] += 1 }
            }
            var issues: [Issue] = []
            if onlyInLibrary > 0 { issues.append(.artworkOnlyInLibrary(tracks: onlyInLibrary)) }
            for (image, count) in notShown.sorted(by: { $0.value > $1.value }) { issues.append(.artworkNotShown(image, tracks: count)) }
            if untagged > 0 { issues.append(.untaggedCompilation(tracks: untagged)) }
            if tracksDiffering > 0 {
                let order = ["title", "artist", "album", "album artist", "track number"]
                issues.append(.tagsDiffer(fields: order.filter { differing[$0] != nil }, tracks: tracksDiffering))
            }
            if unreadable > 0 { issues.append(.unreadable(tracks: unreadable)) }
            if !issues.isEmpty { albums.append(Album(title: key.title, artist: key.artist, issues: issues)) }
        }
        return RockboxReport(installation: installation, albums: albums, scannedTracks: scanned)
    }

    private struct AlbumKey: Hashable {
        let title: String?
        let artist: String?
    }

    /// Empty tags count as missing on both sides; spaces at the ends don't count.
    static func differingFields(_ track: ITTrack, _ tags: FileTags) -> [String] {
        func same(_ a: String?, _ b: String?) -> Bool {
            let x = a?.trimmingCharacters(in: .whitespaces) ?? "", y = b?.trimmingCharacters(in: .whitespaces) ?? ""
            return x == y
        }
        var fields: [String] = []
        if !same(track.title, tags.title) { fields.append("title") }
        if !same(track.artist, tags.artist) { fields.append("artist") }
        if !same(track.album, tags.album) { fields.append("album") }
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty, !same(albumArtist, tags.albumArtist) {
            fields.append("album artist")
        }
        if track.trackNumber != tags.trackNumber { fields.append("track number") }
        return fields
    }

    /// One line per album, for the copied report. Album titles are in it only when the user
    /// copies the Rockbox report itself, not in the general diagnostic report.
    public var reportLines: [String] {
        ["rockbox: \(installation.version ?? "unknown version") · \(installation.target ?? "unknown target") · "
            + "\(scannedTracks) files read · \(albums.count) albums with issues"]
            + albums.flatMap { album in album.issues.map { "  \(album.title ?? "(no album)"): \($0.detail)" } }
    }
}
