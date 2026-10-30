import Foundation
import Testing
@testable import ITDBKit

/// The iPod's own library sync (`OnDeviceSync`): found from its files, owning FLAC entries and
/// videos outside `iPod_Control`, and their files counted as present outside `iPod_Control/Music`.
@Suite("On-device library sync")
struct OnDeviceSyncTests {

    /// A volume with `iPod_Control/Music/F00`; `sync` adds `FLAC/libsync.state` (version 4).
    private func volume(sync: Bool) throws -> (root: URL, paths: IPodPaths) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-sync-\(UUID())")
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.musicDirectory.appendingPathComponent("F00"), withIntermediateDirectories: true)
        if sync {
            let folder = root.appendingPathComponent("FLAC")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(Array("FLSY".utf8) + [4, 0, 0, 0]).write(to: folder.appendingPathComponent("libsync.state"))
        }
        return (root, paths)
    }

    /// The first fixture track as an entry the sync wrote: file type `FLAC`, a file in `/Music`.
    private func flac(_ track: ITTrack, at location: String = ":Music:Synthetic Album:01 Track.flac", marker: [UInt8]? = nil) -> ITTrack {
        var copy = track.setting(.location, to: location)
        copy.rawHeader.set(MhitLayout.fileTypeCode, OnDeviceSync.flacType)
        if let marker { copy.rawHeader.replaceSubrange(OnDeviceSync.markerOffset..<(OnDeviceSync.markerOffset + marker.count), with: marker) }
        return copy
    }

    private func video(_ track: ITTrack, at location: String) -> ITTrack {
        var copy = track.setting(.location, to: location)
        copy.rawHeader.set(MhitLayout.fileTypeCode, OnDeviceSync.videoType)
        return copy
    }

    @Test("detected from its state file, cover cache or firmware image; a plain iPod has none")
    func detection() throws {
        let (plain, _) = try volume(sync: false)
        defer { try? FileManager.default.removeItem(at: plain) }
        #expect(OnDeviceSync.detect(at: plain) == nil)

        let (root, _) = try volume(sync: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(Array("FCDB".utf8) + [1, 0, 0, 0]).write(to: root.appendingPathComponent("FLAC/covers.db"))
        try Data([0]).write(to: root.appendingPathComponent("osos-v18.dec"))
        let sync = try #require(OnDeviceSync.detect(at: root))
        #expect(sync.stateVersion == 4)
        #expect(sync.hasCoverCache)
        #expect(!sync.hasLog)
        #expect(sync.firmwareImages == ["osos-v18.dec"])

        // A user's own folder named FLAC with music in it is not the sync.
        let (other, _) = try volume(sync: false)
        defer { try? FileManager.default.removeItem(at: other) }
        try FileManager.default.createDirectory(at: other.appendingPathComponent("FLAC/Album"), withIntermediateDirectories: true)
        #expect(OnDeviceSync.detect(at: other) == nil)
    }

    @Test("owns every FLAC and videos outside iPod_Control, nothing else")
    func ownership() throws {
        let track = try LibraryFixture.standard().tracks[0]
        #expect(!OnDeviceSync.manages(track), "an MP3 in iPod_Control")
        #expect(OnDeviceSync.manages(flac(track)))
        #expect(OnDeviceSync.manages(video(track, at: ":TV Shows:Show:S01E01.m4v")))
        #expect(!OnDeviceSync.manages(video(track, at: ":iPod_Control:Music:F00:ABCD.m4v")), "a video synced by iTunes")
    }

    @Test("its mark in the header: version, blank or other bytes")
    func markers() throws {
        let track = try LibraryFixture.standard().tracks[0]
        #expect(OnDeviceSync.marker(of: flac(track)) == .blank)
        #expect(OnDeviceSync.marker(of: flac(track, marker: Array("FLSY".utf8) + [4, 0])) == .version(4))
        #expect(OnDeviceSync.marker(of: flac(track, marker: [1, 2, 3, 4])) == .other)
    }

    @Test("with the sync an owned file in /Music is found, not missing; without it the entry has no file")
    func integrity() throws {
        let base = try LibraryFixture.standard()
        let owned = base.tracks[0].uniqueID
        let library = base.mappingTracks { $0.uniqueID == owned ? flac($0) : $0 }
        let synced = try #require(library.tracks.first { $0.uniqueID == owned })

        let (plain, plainPaths) = try volume(sync: false)
        defer { try? FileManager.default.removeItem(at: plain) }
        let (root, paths) = try volume(sync: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for volume in [plain, root] {
            let folder = volume.appendingPathComponent("Music/Synthetic Album")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(count: Int(synced.sizeBytes)).write(to: folder.appendingPathComponent("01 Track.flac"))
        }

        // The fixture's MP3s have no files on either volume.
        let without = try IntegrityReport.build(library: library, paths: plainPaths)
        #expect(without.missingFiles.contains { $0.uniqueID == owned })
        #expect(without.syncedFiles == 0)

        let with = try IntegrityReport.build(library: library, paths: paths)
        #expect(!with.missingFiles.contains { $0.uniqueID == owned })
        #expect(with.missingFiles.count == without.missingFiles.count - 1)
        #expect(with.syncedFiles == 1)
        #expect(with.orphanedFiles.isEmpty)
    }

    @Test("an owned location leading outside the iPod has no file")
    func containment() throws {
        let (root, paths) = try volume(sync: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let track = try LibraryFixture.standard().tracks[0]
        #expect(OnDeviceSync.file(of: flac(track, at: ":..:synthetic-private.flac"), on: paths) == nil)
        #expect(OnDeviceSync.file(of: track, on: paths) == nil, "not owned: its file is only in iPod_Control/Music")
    }

    @Test("report lines: counts and versions, no titles or folder names")
    func reportLines() throws {
        let (root, paths) = try volume(sync: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try LibraryFixture.standard()
        let (first, second) = (base.tracks[0].uniqueID, base.tracks[1].uniqueID)
        let library = base.mappingTracks {
            $0.uniqueID == first ? flac($0, marker: Array("FLSY".utf8) + [4, 0]) : $0.uniqueID == second ? flac($0) : $0
        }
        let sync = try #require(OnDeviceSync.detect(at: root))

        let lines = sync.reportLines(library: library, paths: paths, iTunesDBModified: nil)
        let text = lines.joined(separator: "\n")
        #expect(lines.first?.hasPrefix("devicesync/install: FLAC/libsync.state version 4") == true)
        #expect(text.contains("devicesync/tracks: 2 of \(library.tracks.count) songs owned (2 FLAC, 0 videos outside iPod_Control)"))
        #expect(text.contains("files 0 found, 2 missing"))
        #expect(text.contains("markers FLSY v4 ×1, blank ×1"))
        #expect(!text.contains("Synthetic Album"))
        for track in library.tracks { #expect(!text.contains(try #require(track.title))) }
    }
}
