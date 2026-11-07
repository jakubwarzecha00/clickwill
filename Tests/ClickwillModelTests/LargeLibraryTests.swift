import Foundation
import CoreGraphics
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// A library of any size, assembled in one pass. `addingTracks` updates every browse table
/// per song, which is what a test here measures, so it can't be used to build one.
enum LargeLibrary {

    struct Album {
        let artist, title, genre: String
        let year: UInt32
        var songs: [(title: String, milliseconds: UInt32)]
    }

    /// The same library for the same size.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let words = """
        Amber Anchor Autumn Blue Broken Bright Cedar Cinder Cobalt Cold Copper Crimson Dawn Delta Distant Drift Dust \
        Echo Ember Empty Fading Falling Field Fire Forest Ghost Glass Golden Harbor Hollow Horizon Iron Ivory Lantern \
        Last Lonely Long Lost Lunar Marble Midnight Morning Neon Night North Ocean Paper Pale Quiet Rain River Rust \
        Salt Scarlet Shadow Silent Silver Slow Static Stone Storm Summer Sunset Velvet Violet Water Weather White Wild \
        Winter Wire
        """.split(separator: " ").map(String.init)
    private static let nouns = """
        Atlas Avenue Bay Bells Birds Bridge Canyon Choir City Coast Days Dreams Engine Ferry Fields Garden Heart Hills \
        Home Island Kings Lake Light Lines Machine Mirror Moon Motel Mountain Museum Parade Radio Road Rooms Shore \
        Signal Sky Song Stars Station Street Sun Tide Town Train Valley Waves Window Years
        """.split(separator: " ").map(String.init)
    /// Names outside ASCII: they cost the most when sorting the way the Finder does.
    private static let foreign = "Żółty Łąka Śnieg Źródło Ćma Müller Björk Señor Café Noël Ångström Øresund Čapek Dvořák Живые Река Ночь 夜明け 東京 青空 서울 바다"
        .split(separator: " ").map(String.init)
    private static let sharedAlbums = ["Greatest Hits", "Live", "Unplugged", "Demos", "Self Titled"]
    private static let genres = ["Rock", "Pop", "Jazz", "Ambient", "Folk", "Electronic"]

    static func albums(songs total: Int) -> [Album] {
        var random = Seeded(state: UInt64(total))
        func phrase(foreignShare: Int) -> String {
            let first = Int.random(in: 0..<100, using: &random) < foreignShare
                ? foreign.randomElement(using: &random)! : words.randomElement(using: &random)!
            return "\(first) \(nouns.randomElement(using: &random)!)"
        }
        var albums: [Album] = []
        var artists = Set<String>()
        var count = 0
        while count < total {
            let artist = phrase(foreignShare: 8) + (artists.count > 3000 ? " \(artists.count)" : "")
            guard artists.insert(artist).inserted else { continue }
            let albumCount = [1, 1, 2, 2, 3, 4, 6, 9].randomElement(using: &random)!
            for _ in 0..<albumCount where count < total {
                let title = Int.random(in: 0..<100, using: &random) < 5
                    ? sharedAlbums.randomElement(using: &random)! : phrase(foreignShare: 8)
                let size = min(Int.random(in: 6...18, using: &random), total - count)
                var album = Album(artist: artist, title: title, genre: genres.randomElement(using: &random)!,
                                  year: UInt32.random(in: 1965...2025, using: &random), songs: [])
                var titles = Set<String>()
                for _ in 0..<size {
                    let song = phrase(foreignShare: 5)
                    guard titles.insert(song).inserted else { continue }
                    album.songs.append((song, UInt32.random(in: 150_000...330_000, using: &random)))
                }
                // Every hundredth album has a song twice, so the duplicates bar has something to count.
                if albums.count % 100 == 0, let first = album.songs.first, count + album.songs.count < total {
                    album.songs.append(first)
                }
                count += album.songs.count
                albums.append(album)
            }
        }
        return albums
    }

    /// `base` with its tracks replaced by the generated ones, the browse tables built once.
    /// Records take their shape from the first track of `base`.
    static func build(songs: Int, from base: ITLibrary) throws -> ITLibrary {
        let template = try #require(base.tracks.first)
        var tracks: [ITTrack] = []
        var records: [ITAlbum] = []
        let now = Date()
        for (offset, album) in albums(songs: songs).enumerated() {
            let index = UInt32(offset + 1)
            for (position, song) in album.songs.enumerated() {
                let id = UInt32(tracks.count + 1)
                let draft = TrackDraft(
                    title: song.title, artist: album.artist, albumArtist: album.artist, album: album.title,
                    genre: album.genre, year: album.year, trackNumber: UInt32(position + 1),
                    totalTracks: UInt32(album.songs.count), discNumber: 1, totalDiscs: 1,
                    durationMilliseconds: song.milliseconds, sizeBytes: 4_000_000, bitRate: 192, sampleRate: 44_100,
                    kind: template.fileKind ?? .mp3,
                    relativePath: "iPod_Control/Music/F\(String(format: "%02d", id % 50))/\(id).\(template.fileKind?.fileExtension ?? "mp3")")
                if position == 0 {
                    records.append(ITLibrary.makingAlbum(from: draft, template: base.albums.last, index: UInt16(clamping: index),
                                                         persistentID: ITLibrary.albumIdentitySpace | UInt64(index)))
                }
                tracks.append(base.makingTrack(from: draft, template: template, uniqueID: id,
                                               persistentID: 0x1000_0000_0000 + UInt64(id), albumRecordIndex: index,
                                               inheritingSortFieldsFrom: nil, now: now))
            }
        }

        var copy = base
        copy.sections = try base.sections.map { section in
            var changed = section
            switch section.content {
            case .tracks: changed.content = .tracks(tracks)
            case .albums: changed.content = .albums(records)
            case .playlists(let playlists):
                changed.content = .playlists(try playlists.filter(\.isMaster).map { try tables(of: $0, for: tracks) })
            case .opaque: break
            }
            return changed
        }
        return copy
    }

    private static func tables(of playlist: ITPlaylist, for tracks: [ITTrack]) throws -> ITPlaylist {
        var result = playlist
        let entry = try #require(playlist.entries.last)
        result.entries = tracks.enumerated().map { offset, track in
            var new = entry
            new.trackID = track.uniqueID
            new.order = UInt32(offset + 1)
            return new
        }
        var orders: [UInt32: [UInt32]] = [:]
        func order(_ criterion: BrowseIndex.Criterion) -> [UInt32] {
            if let known = orders[criterion.rawValue] { return known }
            let keys = tracks.map { ITLibrary.browseKey(criterion, for: $0) }
            let sorted = keys.indices.sorted { keys[$0] != keys[$1] ? keys[$0] < keys[$1] : $0 < $1 }.map { UInt32($0) }
            orders[criterion.rawValue] = sorted
            return sorted
        }
        func resolved(_ criterion: BrowseIndex.Criterion) -> BrowseIndex.Criterion {
            ITLibrary.knownCriteria.contains(criterion) ? criterion : .title
        }
        result.mhods = playlist.mhods.map { mhod in
            if var index = BrowseIndex(mhod: mhod) {
                index.entries = order(resolved(index.criterion))
                return index.mhod()
            }
            if let jump = AlphabetJumpTable(mhod: mhod) {
                let criterion = resolved(jump.criterion)
                return jump.rebuilt(fromRuns: order(criterion).map { (ITLibrary.letterCode(criterion, for: tracks[Int($0)]), 1) }).mhod()
            }
            return mhod
        }
        return result
    }

    /// A cover of our own: two colors from the name, diagonal stripes.
    static func cover(_ name: String) throws -> CGImage {
        var random = Seeded(state: UInt64(truncatingIfNeeded: name.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }))
        func color() -> CGColor {
            CGColor(red: .random(in: 0...1, using: &random), green: .random(in: 0...1, using: &random),
                    blue: .random(in: 0...1, using: &random), alpha: 1)
        }
        let context = try #require(CGContext(data: nil, width: 320, height: 320, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(color())
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
        context.setStrokeColor(color())
        context.setLineWidth(.random(in: 10...40, using: &random))
        for offset in stride(from: -320, to: 640, by: 80) {
            context.move(to: CGPoint(x: offset, y: 0))
            context.addLine(to: CGPoint(x: offset + 320, y: 320))
        }
        context.strokePath()
        return try #require(context.makeImage())
    }
}

/// How the library behaves at the size of a full iPod classic. Prints a time per step;
/// `LARGE_LIBRARY_SONGS` sets the size. The limits are about ten times what a debug build takes
/// on an M5, for a slow CI machine: they catch something growing out of hand, not a slower day.
@Suite("Large library")
@MainActor
struct LargeLibraryTests {

    nonisolated private static let environment = ProcessInfo.processInfo.environment
    private var songs: Int { Self.environment["LARGE_LIBRARY_SONGS"].flatMap(Int.init) ?? 15_000 }

    /// A row of the Songs table, with the same fields sorted the same way.
    private struct Row {
        let title, artist, album: String
        let duration: TimeInterval
    }

    private func time<T>(_ label: String, limit: Duration? = nil, _ body: () throws -> T) rethrows -> T {
        let clock = ContinuousClock()
        var result: T?
        let elapsed = try clock.measure { result = try body() }
        report(label, elapsed, limit: limit)
        return result!
    }

    private func time<T>(_ label: String, limit: Duration? = nil, _ body: () async throws -> T) async rethrows -> T {
        let started = ContinuousClock.now
        let result = try await body()
        report(label, ContinuousClock.now - started, limit: limit)
        return result
    }

    /// `limit` is for 15,000 songs and grows with the library.
    private func report(_ label: String, _ elapsed: Duration, limit: Duration?) {
        let (seconds, attoseconds) = elapsed.components
        print("LARGE \(songs) \(label): \(seconds * 1000 + attoseconds / 1_000_000_000_000_000) ms")
        if let limit {
            let scaled = limit * max(1, Double(songs) / 15_000)
            #expect(elapsed <= scaled, "\(label) took \(elapsed), the limit is \(scaled)")
        }
    }

    /// The fake iPod from the write tests holding the large library, signed.
    private func rig() async throws -> WriteTests.Rig {
        let rig = try await WriteTests.rig()
        let large = try time("build") { try LargeLibrary.build(songs: songs, from: try rig.onDisk()) }
        try Hash58.sign(ITunesDBWriter.serialize(large), fireWireID: Hash58.fireWireID(fromHex: WriteTests.guid))
            .write(to: rig.paths.iTunesDB)
        return rig
    }

    @Test("the library assembled here reads back whole")
    func assembled() async throws {
        let rig = try await rig(); defer { rig.cleanUp() }
        let bytes = try Data(contentsOf: rig.paths.iTunesDB)
        let parsed = try ITunesDBParser.parse(bytes)
        #expect(parsed.tracks.count == songs)
        #expect(ITunesDBWriter.serialize(parsed) == bytes)
    }

    @Test("reading and showing")
    func reading() async throws {
        let rig = try await rig(); defer { rig.cleanUp() }
        let bytes = try Data(contentsOf: rig.paths.iTunesDB)
        _ = try time("parse \(bytes.count / 1024) KB") { try ITunesDBParser.parse(bytes) }
        let device = try IPodDevice.open(try #require(IPodVolume.at(rig.paths.mountPoint)))
        let model = rig.model
        await time("load", limit: .seconds(30)) { await model.load(.device(device)) }
        #expect(model.state == .loaded)
        await time("format scan, no files", limit: .seconds(60)) { await model.formatScan?.value }
        time("cards", limit: .seconds(1)) { model.rebuildCards() }

        let rows = time("songs: rows", limit: .seconds(1)) {
            model.albums.flatMap { album in
                model.tracks(of: album).map { Row(title: $0.displayTitle, artist: $0.artist, album: album.displayTitle, duration: $0.duration) }
            }
        }
        #expect(rows.count == songs)
        _ = time("songs: sort by title", limit: .seconds(5)) { rows.sorted(using: [KeyPathComparator(\Row.title)]) }
        _ = time("songs: sort by artist", limit: .seconds(5)) { rows.sorted(using: [KeyPathComparator(\Row.artist)]) }
        _ = time("songs: sort by album", limit: .seconds(5)) { rows.sorted(using: [KeyPathComparator(\Row.album)]) }
        _ = time("songs: sort by time", limit: .seconds(5)) { rows.sorted(using: [KeyPathComparator(\Row.duration)]) }
        _ = time("songs: search", limit: .seconds(1)) {
            rows.filter { $0.title.localizedStandardContains("riv") || $0.artist.localizedStandardContains("riv") || $0.album.localizedStandardContains("riv") }
        }
        _ = time("songs: duplicates", limit: .seconds(2)) { model.duplicateGroups() }
        #expect(!model.duplicateGroups().isEmpty)
        let counted = await model.duplicateCount()
        #expect(counted == model.duplicateGroups().count, "the bar above the table and the review sheet agree")
        _ = time("artists: rows", limit: .seconds(1)) {
            model.albums.reduce(into: [String: Int]()) { $0[$1.displayArtist, default: 0] += model.tracks(of: $1).count }
        }
        _ = time("artists: count") { model.artistCount }
    }

    @Test("editing and writing")
    func writing() async throws {
        let rig = try await rig(); defer { rig.cleanUp() }
        let device = try IPodDevice.open(try #require(IPodVolume.at(rig.paths.mountPoint)))
        let model = rig.model
        await model.load(.device(device))
        await model.formatScan?.value

        let library = try rig.onDisk()
        let draft = TrackDraft(title: "New Song", artist: "New Artist", albumArtist: "New Artist", album: "New Album",
                               durationMilliseconds: 200_000, sizeBytes: 4_000_000, bitRate: 192, sampleRate: 44_100,
                               kind: .mp3, relativePath: "iPod_Control/Music/F00/new.mp3")
        _ = try time("add one song to the database", limit: .seconds(30)) { try library.addingTracks([draft]) }

        let album = try #require(model.albums.first)
        _ = try time("edit: album field", limit: .seconds(2)) { try model.setAlbumField(album, .year, to: "1999") }
        let row = try #require(model.tracks(of: model.albums[1]).first)
        try time("edit: delete a song", limit: .seconds(2)) { try model.deleteTrack(row, in: model.albums[1]) }
        try time("edit: delete an album", limit: .seconds(2)) { _ = try model.deleteAlbum(model.albums[2]) }
        _ = try await time("write", limit: .seconds(30)) { try await model.apply() }
        #expect(try rig.signedWithDeviceKey())
    }

    /// Not a test but a way to open the library in the app:
    /// `LARGE_LIBRARY_OUT=<folder> LARGE_LIBRARY_BASE=<iTunesDB> LARGE_LIBRARY_SONGS=15000 swift test --filter makeSnapshot`,
    /// then `--demo --snapshot <folder>`. Needs a base database with an album list.
    @Test("a snapshot with covers", .enabled(if: environment["LARGE_LIBRARY_OUT"] != nil))
    func makeSnapshot() async throws {
        let out = URL(fileURLWithPath: try #require(Self.environment["LARGE_LIBRARY_OUT"]), isDirectory: true)
        let base = try ITunesDBParser.parse(Data(contentsOf: URL(fileURLWithPath: try #require(Self.environment["LARGE_LIBRARY_BASE"]))))
        var library = try LargeLibrary.build(songs: songs, from: base)

        let files = out.appendingPathComponent("files", isDirectory: true)
        let paths = IPodPaths(mountPoint: FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-large-\(UUID().uuidString)", isDirectory: true))
        try FileManager.default.createDirectory(at: paths.artworkDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: paths.mountPoint) }
        // The iPod classic formats, as in `ipodctl demo-snapshot`.
        let formats: [DeviceDescription.ImageFormat] = [
            .init(formatID: 1055, width: 128, height: 128, pixelFormat: "L565"),
            .init(formatID: 1060, width: 320, height: 320, pixelFormat: "L565"),
            .init(formatID: 1061, width: 55, height: 55, pixelFormat: "L565"),
        ]
        var firstOfAlbum: [String: ITTrack] = [:]
        var counts: [String: Int] = [:]
        for track in library.tracks {
            let title = track.album ?? ""
            if firstOfAlbum[title] == nil { firstOfAlbum[title] = track }
            counts[title, default: 0] += 1
        }
        for (title, owner) in firstOfAlbum {
            let image = try LargeLibrary.cover(title)
            _ = try ArtworkAddition.add(ownerPersistentID: owner.persistentID, sourceByteCount: 50_000,
                                        trackCount: UInt32(counts[title] ?? 1), in: paths, deviceFormats: formats) { width, height in
                try ITHMBImage(rendering: image, width: width, height: height)
            }
            library = library.linkingAlbumArtwork(album: title, ownerPersistentID: owner.persistentID)
                .markingAlbumArtwork(album: title, sourceByteCount: 50_000)
        }
        try FileManager.default.createDirectory(at: files.appendingPathComponent("iTunes"), withIntermediateDirectories: true)
        try ITunesDBWriter.serialize(library).write(to: files.appendingPathComponent("iTunes/iTunesDB"))
        try FileManager.default.copyItem(at: paths.artworkDirectory, to: files.appendingPathComponent("Artwork"))
        print("LARGE snapshot: \(out.path), \(library.tracks.count) songs, \(firstOfAlbum.count) albums")

        // With `LARGE_LIBRARY_DEVICE=<folder>` and `LARGE_LIBRARY_AUDIO=<short file>`: also the layout of an
        // iPod, signed, with a file per song - for a disk image the app opens as a device.
        guard let root = Self.environment["LARGE_LIBRARY_DEVICE"], let audio = Self.environment["LARGE_LIBRARY_AUDIO"] else { return }
        let device = IPodPaths(mountPoint: URL(fileURLWithPath: root, isDirectory: true))
        for folder in 0..<50 {
            try FileManager.default.createDirectory(at: device.musicDirectory.appendingPathComponent(String(format: "F%02d", folder)), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: device.sysInfoExtended.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: device.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: paths.artworkDirectory, to: device.artworkDirectory)
        try Hash58.sign(ITunesDBWriter.serialize(library), fireWireID: Hash58.fireWireID(fromHex: WriteTests.guid)).write(to: device.iTunesDB)
        try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>FireWireGUID</key><string>\(WriteTests.guid)</string></dict></plist>
            """.utf8).write(to: device.sysInfoExtended)
        let source = URL(fileURLWithPath: audio)
        for track in library.tracks {
            try FileManager.default.copyItem(at: source, to: device.mountPoint.appendingPathComponent(try #require(track.relativePath)))
        }
    }
}
