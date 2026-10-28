import Foundation
import ITDBKit
import ClickwillModel

/// `demo-snapshot --base ITUNESDB --spec LIBRARY.json --out FOLDER`
/// - a demo library for screenshots and ads, described by a JSON spec: fictional
/// artists, our own artwork, silent files. `--base` is an iTunesDB written by Apple, from which
/// the database layout is kept. Files on disk only - no iPod, no signature, no write
/// to a device. The app opens the result: `--snapshot FOLDER`.
enum DemoSnapshotCommand {
    static func run(_ call: Invocation) async throws {
        guard let base = call.value(for: "--base"), let specPath = call.value(for: "--spec"), let outPath = call.value(for: "--out") else {
            throw CommandError("demo-snapshot needs --base <iTunesDB>, --spec <library.json> and --out <folder>")
        }
        let specURL = URL(fileURLWithPath: (specPath as NSString).expandingTildeInPath)
        let here = specURL.deletingLastPathComponent()
        let out = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: out.path) else { throw CommandError("\(out.path) already exists - remove it or give another one") }
        struct Album: Decodable { let artist, album, genre: String; let year: UInt32; let tracks: [String] }
        struct Spec: Decodable { let ipodName: String; let albums: [Album] }
        let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: specURL))
        func slug(_ text: String) -> String {
            let lowered = text.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
            return String(lowered).split(separator: "-").joined(separator: "-")
        }

        // An empty library in Apple's layout: the user's tracks and playlists drop out,
        // the master playlist gets a neutral name (it was the iPod's name, with a person's name in it).
        var library = try ITunesDBParser.parse(try Data(contentsOf: URL(fileURLWithPath: (base as NSString).expandingTildeInPath)))
        // One Apple Lossless track stays for the duration of adding as a record template
        // (we do not write the first track in a given format from scratch); removed at the end.
        guard let template = library.tracks.first(where: { $0.fileKind == .appleLossless }) else {
            throw CommandError("the base database has no Apple Lossless track - one is needed as a template")
        }
        library = try library.removingTracks(uniqueIDs: Set(library.tracks.map(\.uniqueID)).subtracting([template.uniqueID]))
            .removingOrphanedAlbumRecords()
        for index in library.sections.indices {
            guard case .playlists(let playlists) = library.sections[index].content else { continue }
            let kept = playlists.filter(\.isMaster).map { playlist -> ITPlaylist in
                var playlist = playlist
                playlist.mhods = playlist.mhods.map { $0.type == .title ? $0.replacingText(spec.ipodName) : $0 }
                return playlist
            }
            library.sections[index].content = .playlists(kept)
        }
        print("Empty database: \(library.tracks.count) tracks, \(library.albums.count) albums")

        // A stand-in volume: the iPod classic layout in a temporary folder.
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-demo-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: mount)
        for folder in (0..<50).map({ String(format: "F%02d", $0) }) {
            try FileManager.default.createDirectory(at: paths.musicDirectory.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: paths.iTunesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: mount) }

        // iPod classic artwork formats (measured on a 7G: Music writes 1055, 1060, 1061).
        let sysInfo = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>AlbumArt</key><array>
        <dict><key>FormatId</key><integer>1055</integer><key>RenderWidth</key><integer>128</integer><key>RenderHeight</key><integer>128</integer><key>PixelFormat</key><string>4C353635</string></dict>
        <dict><key>FormatId</key><integer>1060</integer><key>RenderWidth</key><integer>320</integer><key>RenderHeight</key><integer>320</integer><key>PixelFormat</key><string>4C353635</string></dict>
        <dict><key>FormatId</key><integer>1061</integer><key>RenderWidth</key><integer>55</integer><key>RenderHeight</key><integer>55</integer><key>PixelFormat</key><string>4C353635</string></dict>
        </array></dict></plist>
        """
        let formats = try DeviceDescription.parse(xml: Data(sysInfo.utf8)).albumArt

        var additions: [PendingAddition] = []
        for album in spec.albums {
            let key = "\(slug(album.artist))--\(slug(album.album))"
            let cover = here.appendingPathComponent("covers/\(key).png")
            guard FileManager.default.fileExists(atPath: cover.path) else { throw CommandError("missing artwork \(cover.path) - run covers.py") }
            for (offset, title) in album.tracks.enumerated() {
                let file = here.appendingPathComponent(String(format: "audio/%@/%02d.m4a", key, offset + 1))
                let candidate = try await AudioImport.candidate(at: file)
                var draft = candidate.draft
                draft.title = title
                draft.artist = album.artist
                draft.albumArtist = album.artist
                draft.album = album.album
                draft.genre = album.genre
                draft.year = album.year
                draft.trackNumber = UInt32(offset + 1)
                draft.totalTracks = UInt32(album.tracks.count)
                draft.discNumber = 1
                draft.totalDiscs = 1
                additions.append(PendingAddition(id: UUID(), draft: draft, source: file, verdict: candidate.verdict,
                                                 formatLabel: candidate.formatLabel, cover: .file(cover)))
            }
        }
        print("Adding \(additions.count) tracks from \(spec.albums.count) albums")
        let outcome = await TrackAdditionRunner.run(additions, into: library, paths: paths, artworkFormats: formats)
        for problem in outcome.failed + outcome.coversFailed { print("  WARNING: \(problem)") }
        guard outcome.failed.isEmpty, outcome.coversFailed.isEmpty, !outcome.aborted else { throw CommandError("the build did not pass - writing nothing") }

        let finished = try outcome.library.removingTracks(uniqueIDs: [template.uniqueID]).removingOrphanedAlbumRecords()
        let bytes = ITunesDBWriter.serialize(finished)
        let reparsed = try ITunesDBParser.parse(bytes)
        guard ITunesDBWriter.serialize(reparsed) == bytes else { throw CommandError("write -> read -> write mismatch") }
        let names = Set(spec.albums.map(\.album))
        guard reparsed.tracks.allSatisfy({ names.contains($0.album ?? "") }) else { throw CommandError("a track from outside the demo library remained in the database") }
        let files = out.appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(at: files.appendingPathComponent("iTunes"), withIntermediateDirectories: true)
        try bytes.write(to: files.appendingPathComponent("iTunes/iTunesDB"))
        try FileManager.default.copyItem(at: paths.artworkDirectory, to: files.appendingPathComponent("Artwork"))
        // A check the same way the app goes: album artwork owner -> mhii -> .ithmb file.
        let artwork = try ArtworkDBParser.parse(try Data(contentsOf: files.appendingPathComponent("Artwork/ArtworkDB")))
        let byTrack = artwork.indexedByTrack()
        let owners = reparsed.albums.map(\.artworkOwnerPersistentID)
        let linked = owners.filter { byTrack[$0] != nil }.count
        let tracksWithImage = reparsed.tracks.filter { byTrack[$0.persistentID] != nil }.count
        print("Done: \(out.path)")
        print("  tracks \(reparsed.tracks.count), albums \(reparsed.albums.count), artwork \(outcome.covers)")
        print("  mhii: \(artwork.images.count), albums with artwork through 0x20: \(linked)/\(owners.count), tracks with an image: \(tracksWithImage)")
        // Exactly the app's path: snapshot -> links -> ArtworkDB from disk.
        let session = try LibrarySession.open(.snapshot(out))
        let check = session.paths
        guard let appArtwork = session.artwork else { throw CommandError("the app will not find ArtworkDB at \(check.artworkDB.path)") }
        let appByTrack = appArtwork.indexedByTrack()
        var decodedCount = 0
        for owner in owners {
            guard let entry = appByTrack[owner], let variant = entry.largest else { print("  no variant for \(owner)"); continue }
            do { _ = try ITHMB.read(variant, in: check).makeCGImage(); decodedCount += 1 }
            catch { print("  decoding \(owner): \(error)") }
        }
        print("  decoded artwork (checked as in the app): \(decodedCount)/\(owners.count)")
    }
}
