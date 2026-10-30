import Foundation
import Testing
@testable import ITDBKit

/// What the report carries beyond the checks: enough to find the cause on a model we never
/// held, and to tell how a write reached the Apple firmware and Rockbox.
@Suite("Diagnostic measurements")
struct DiagnosticsMeasurementsTests {

    /// Built by Rockbox's own database code (`tools/database`, ipodvideo) from
    /// `/Music/Own/Private Title.mp3`, `/iPod_Control/Music/F00/ABCD.mp3`, `/iPod_Control/Music/F01/EFGH.m4a`.
    static let rockboxIndex = Data(base64Encoded: """
        EEhDVJgCAAADAAAAAAAAAAEAAAAAAAAADAAAAAwAAAAMAAAADAAAAAwAAAAMAAAADAAAAAwAAAAMAAAA1wcAAAEAAAADAAAADAAA\
        AMEAAADQDwAAAAAAAAAAAAAAAAAAAAAAAAAAAADydORqAAAAAAAAAAAAAAAADAAAAAwAAAAMAAAANAAAADEAAAAMAAAADAAAAAwA\
        AAAMAAAA1wcAAAEAAAADAAAADAAAAMEAAADQDwAAAAAAAAAAAAAAAAAAAAAAAAAAAADxdORqAAAAAAAAAAAAAAAADAAAAAwAAAAM\
        AAAAXAAAAFoAAAAMAAAADAAAAAwAAAAMAAAA1wcAAAEAAAADAAAADAAAANoAAAC3DwAAAAAAAAAAAAAAAAAAAAAAAAAAAADxdORq\
        AAAAAAAAAAAAAAAA
        """)!
    static let rockboxFilenames = Data(base64Encoded: """
        EEhDVHcAAAADAAAAHQAAAAAAAAAvTXVzaWMvT3duL1ByaXZhdGUgVGl0bGUubXAzACEAAAABAAAAL2lQb2RfQ29udHJvbC9NdXNp\
        Yy9GMDAvQUJDRC5tcDMAIQAAAAIAAAAvaVBvZF9Db250cm9sL011c2ljL0YwMS9FRkdILm00YQA=
        """)!

    @Test("Rockbox's database as Rockbox wrote it: version, entries, paths")
    func rockboxDatabase() throws {
        let database = try RockboxDatabase.parse(index: Self.rockboxIndex, filenames: Self.rockboxFilenames)
        #expect(database.version == 0x10)
        #expect(database.entries == 3)
        #expect(database.deleted == 0)
        #expect(Set(database.paths) == ["/Music/Own/Private Title.mp3", "/iPod_Control/Music/F00/ABCD.mp3", "/iPod_Control/Music/F01/EFGH.m4a"])

        // The flags are the last field of an entry (96 B in 4.0): mark the first one deleted.
        var index = [UInt8](Self.rockboxIndex)
        index[24 + 96 - 4] |= 0x01
        let marked = try RockboxDatabase.parse(index: Data(index), filenames: Self.rockboxFilenames)
        #expect(marked.deleted == 1)
        #expect(marked.paths.count == 2)

        var foreign = [UInt8](Self.rockboxIndex)
        foreign[1] = 0x00
        #expect(throws: RockboxDatabase.ReadError.self) { try RockboxDatabase.parse(index: Data(foreign), filenames: Self.rockboxFilenames) }
    }

    @Test("settings: defaults filled in, older names kept, owner's folder names not reported")
    func rockboxSettings() {
        let settings = RockboxProbe.parseSettings("""
            # comment
            volume: -20
            tagcache_autoupdate: on
            database scan paths: /Music/Anna:/iPod_Control
            tagcache_old_name: yes
            """)
        #expect(settings.first { $0.key == "tagcache_autoupdate" } == .init(key: "tagcache_autoupdate", value: "on", isDefault: false))
        #expect(settings.first { $0.key == "dircache" }?.isDefault == true)
        #expect(settings.contains { $0.key == "tagcache_old_name" })
        #expect(!settings.contains { $0.key == "volume" })
        let paths = settings.first { $0.key == "database scan paths" }!
        #expect(RockboxProbe.reported(paths) == "2 paths, iPod_Control covered")
        #expect(RockboxProbe.reported(.init(key: "database scan paths", value: "/Music", isDefault: false)) == "1 paths, iPod_Control not covered")
    }

    /// An index and file name file in Rockbox's layout for `paths`.
    static func rockboxFiles(_ paths: [String]) -> (index: Data, filenames: Data) {
        func u32(_ value: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(value).littleEndian, Array.init) }
        var names: [UInt8] = []
        var seeks: [Int] = []
        for (entry, path) in paths.enumerated() {
            seeks.append(12 + names.count)
            let bytes = Array(path.utf8) + [0]
            names += u32(bytes.count) + u32(entry) + bytes
        }
        let magic = 0x5443_4810, tags = 23
        var index = u32(magic) + u32(0) + u32(paths.count) + u32(0) + u32(1) + u32(0)
        for seek in seeks { index += (0..<tags).flatMap { $0 == 4 ? u32(seek) : u32(0) } + u32(0) }
        return (Data(index), Data(u32(magic) + u32(names.count) + u32(paths.count) + names))
    }

    @Test("coverage: songs Rockbox doesn't list yet, entries for removed files, files outside iPod_Control")
    func rockboxCoverage() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let library = try ITunesDBParser.parse(try Data(contentsOf: rig.paths.iTunesDB))
        let songs = library.tracks.compactMap(\.relativePath)
        for song in songs.dropLast() {
            let url = try #require(rig.paths.musicFile(song))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        // Rockbox knows every song but the first; the last one's file is gone; one file of its own.
        let known = songs.dropFirst().map { "/" + $0.uppercased() } + ["/Music/Own/x.mp3"]
        let files = Self.rockboxFiles(known)
        let folder = rig.paths.mountPoint.appendingPathComponent(".rockbox")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try files.index.write(to: folder.appendingPathComponent("database_idx.tcd"))
        try files.filenames.write(to: folder.appendingPathComponent("database_4.tcd"))
        try "Version: 4.0\nTarget: ipodvideo\n".write(to: folder.appendingPathComponent("rockbox-info.txt"), atomically: true, encoding: .utf8)

        let probe = try #require(RockboxProbe.read(at: rig.paths.mountPoint))
        let coverage = try #require(probe.coverage(of: library, paths: rig.paths))
        #expect(coverage == .init(songs: songs.count, inRockbox: songs.count - 1, staleEntries: 1, otherEntries: 1))
        #expect(!probe.autoUpdate)

        let lines = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .standard), isMusicRunning: { false }).measurements
        #expect(lines.contains { $0.hasPrefix("rockbox/coverage: \(songs.count) songs in iTunesDB · \(songs.count - 1) in Rockbox database · 1 not in it") })
        #expect(lines.contains { $0.hasSuffix("only after Database › Update Now (tagcache_autoupdate off)") })
        #expect(!lines.joined().contains("Own"), "no folder or file names of the owner")
    }

    @Test("Play Counts newer than iTunesDB and one entry per song: the Apple firmware loaded it")
    func firmwareLoad() throws {
        let rig = try WritePolicyTests.rig(); defer { rig.cleanUp() }
        let device = rig.device(WritePolicyTests.video, policy: .standard)
        let library = try device.readLibrary()
        let written = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: rig.paths.iTunesDB.path)
        #expect(Diagnostics.firmwareLoad(device, library, iTunesDBModified: written).hasPrefix("no Play Counts"))

        try WritePolicyTests.playCounts(tracks: library.tracks.count).write(to: rig.paths.playCounts)
        try FileManager.default.setAttributes([.modificationDate: written.addingTimeInterval(65)], ofItemAtPath: rig.paths.playCounts.path)
        #expect(Diagnostics.firmwareLoad(device, library, iTunesDBModified: written)
            == "Play Counts written 1 min after iTunesDB · \(library.tracks.count) entries for \(library.tracks.count) songs · the Apple firmware loaded this iTunesDB")

        try FileManager.default.setAttributes([.modificationDate: written.addingTimeInterval(-7200)], ofItemAtPath: rig.paths.playCounts.path)
        #expect(Diagnostics.firmwareLoad(device, library, iTunesDBModified: written).hasSuffix("2 h 0 min before iTunesDB · \(library.tracks.count) entries for \(library.tracks.count) songs · written for another iTunesDB"))
    }

    @Test("the record map names every record and its shape, from headers alone")
    func recordMap() throws {
        let database = try WritePolicyTests.unsignedDatabase()
        let library = try ITunesDBParser.parse(database)
        let map = RecordMap.build(database)
        #expect(map.uncovered == 0)
        #expect(map.records.filter { $0.tag == "mhit" }.count == library.tracks.count)
        let mhit = try #require(map.records.first { $0.tag == "mhit" })
        #expect(map.skeleton.hasPrefix("mhbd "))
        #expect(map.skeleton.contains("mhit \(mhit.headerLength) ×\(library.tracks.count)"))
        let location = try #require(map.locate(mhit.offset + 0x0C))
        #expect(location.path == "mhbd > mhsd[type 1] > mhlt > mhit #0")
        #expect(location.inHeader && !location.isText)
        let title = try #require(map.records.first { $0.tag == "mhod" && $0.type == 1 })
        #expect(map.locate(title.offset + title.headerLength + 4)?.isText == true)
    }

    @Test("a database that doesn't rebuild: the report names the record and field, never the text")
    func rebuildNamesTheField() throws {
        var bytes = [UInt8](try WritePolicyTests.unsignedDatabase())
        let map = RecordMap.build(Data(bytes))
        // One mhod fewer in the count at mhit 0x0C: the parser takes the count, the writer
        // drops the extra one, and the count byte is the first that differs.
        let mhit = try #require(map.records.first { $0.tag == "mhit" })
        bytes[mhit.offset + 0x0C] -= 1
        let rig = try WritePolicyTests.rig(database: Data(bytes)); defer { rig.cleanUp() }
        let result = Diagnostics.run(on: rig.device(WritePolicyTests.video, policy: .standard), isMusicRunning: { false })
        #expect(result[.rebuild]?.status == .failed)
        let diffs = result.measurements.filter { $0.hasPrefix("rebuild/") }
        #expect(diffs.contains { $0.hasPrefix("rebuild/rebuilt structure:") })
        #expect(diffs.contains { $0.hasPrefix("rebuild/record: mhbd > mhsd[type 1] > mhlt > mhit #0 ·") && $0.contains("children mhod") }, "\(diffs)")
        #expect(!diffs.contains { $0.contains("mhbd +0x8 (header)") }, "a length that only follows the cause isn't listed")
        #expect(result.reportLines.contains("verdict: Read-only: rebuild didn't pass."))
        let titles = try ITunesDBParser.parse(try WritePolicyTests.unsignedDatabase()).tracks.compactMap(\.title)
        #expect(!titles.contains { title in result.reportLines.contains { $0.contains(title) } })
    }
}
