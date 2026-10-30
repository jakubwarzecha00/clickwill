import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// What Rockbox would show differently from Apple's firmware, album by album - with the
/// tag reader replaced, so the test decides what each file says.
@Suite("Rockbox report")
struct RockboxReportTests {

    static let paths = IPodPaths(mountPoint: URL(fileURLWithPath: "/tmp/rockbox-report"))
    static let installation = RockboxInstallation(version: "4.0", target: "ipodvideo")

    /// Tags exactly as in the library, with an embedded baseline JPEG.
    static func matching(_ track: ITTrack) -> RockboxReport.FileTags {
        RockboxReport.FileTags(title: track.title, artist: track.artist, album: track.album, albumArtist: track.albumArtist,
                               trackNumber: track.trackNumber, image: .jpeg)
    }

    static func report(_ library: ITLibrary, tags: @escaping @Sendable (ITTrack) -> RockboxReport.FileTags?) async -> RockboxReport {
        let byFile = Dictionary(uniqueKeysWithValues: library.tracks.compactMap { track in
            track.fileURL(on: paths).map { ($0, track) }
        })
        return await RockboxReport.build(library: library, paths: paths, installation: installation, progress: nil) { url in
            byFile[url].flatMap(tags)
        }
    }

    static func library() throws -> ITLibrary { try ITunesDBParser.parse(SyntheticLibrary.database()) }

    @Test("files that match the library and carry a JPEG: nothing to report")
    func clean() async throws {
        let library = try Self.library()
        let report = await Self.report(library) { Self.matching($0) }
        #expect(report.albums.isEmpty)
        #expect(report.scannedTracks == library.tracks.count)
    }

    @Test("each issue lands on its album, technical detail included")
    func issues() async throws {
        let library = try Self.library().mappingTracks { track in
            switch track.uniqueID {
            case 15, 16: { var compilation = track; compilation.isCompilation = true; return compilation }()
            case 11: track.markingArtwork(imageSourceByteCount: 5000)
            default: track
            }
        }
        let report = await Self.report(library) { track in
            var tags = Self.matching(track)
            switch track.uniqueID {
            case 10: tags.title = "Bones (old title)"            // renamed only in the library
            case 11: tags.image = nil                           // artwork only in ArtworkDB
            case 13: tags.image = .png
            case 15, 16: tags.albumArtist = nil                 // compilation without album artist
            case 14: return nil                                 // unreadable
            default: break
            }
            return tags
        }
        let byTitle = Dictionary(uniqueKeysWithValues: report.albums.map { ($0.title ?? "", $0.issues) })
        #expect(byTitle["The Bends"] == [.tagsDiffer(fields: ["title"], tracks: 1), .unreadable(tracks: 1)])
        #expect(byTitle["Aftermath"] == [.artworkOnlyInLibrary(tracks: 1), .artworkNotShown(.png, tracks: 1)])
        #expect(byTitle["Currents"] == [.untaggedCompilation(tracks: 2)])
        #expect(report.reportLines.first == "rockbox: 4.0 · ipodvideo · 7 files read · 3 albums with issues")
        #expect(RockboxReport.Issue.artworkNotShown(.png, tracks: 1).detail
            == "embedded PNG in 1 files · Rockbox decodes baseline JPEG only")
    }
}
