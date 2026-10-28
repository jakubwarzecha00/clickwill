import Foundation
import Testing
@testable import ITDBKit

@Suite("Replacing a track's file")
struct FileReplacementTests {

    @Test("the copy goes to the given Fxx folder under a four-letter name")
    func place() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("place-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.musicDirectory, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.m4a")
        try Data(repeating: 7, count: 2048).write(to: source)

        let placement = try FileReplacement.place(source, in: paths, preferredDirectory: "F19")
        #expect(placement.sizeBytes == 2048)
        #expect(placement.relativePath.hasPrefix("iPod_Control/Music/F19/"))
        #expect(placement.url.lastPathComponent.count == 8)   // XXXX.m4a
        #expect(placement.url.pathExtension == "m4a")
        #expect(FileManager.default.fileExists(atPath: placement.url.path))
        #expect(root.appendingPathComponent(placement.relativePath).path == placement.url.path)
    }

    @Test("not enough space: the refusal gives the space needed including the reserve")
    func spaceRefusalCountsReserve() {
        let reserve = FileReplacement.spaceReserve
        #expect(FileReplacement.spaceRefusal(fileSize: 1000, free: 1_600_000)
                == .notEnoughSpace(needed: 1000 + reserve, available: 1_600_000, on: .iPod(reserve: reserve)))
        #expect(FileReplacement.spaceRefusal(fileSize: 1000, free: 1000 + reserve) == nil)
        #expect(FileReplacement.spaceRefusal(fileSize: 1000, free: 999 + reserve) != nil)
    }

    @Test("without a given folder the file goes only to Fxx folders that already exist")
    func placeOnlyInExistingFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("place3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IPodPaths(mountPoint: root)
        // The layout as on a nano 2G: F00-F13, plus junk that is not music folders.
        for index in 0..<14 {
            try FileManager.default.createDirectory(at: paths.musicDirectory.appendingPathComponent(String(format: "F%02d", index)),
                                                    withIntermediateDirectories: true)
        }
        try Data([1]).write(to: paths.musicDirectory.appendingPathComponent("F99"))   // a file, not a folder
        try FileManager.default.createDirectory(at: paths.musicDirectory.appendingPathComponent("Fxx"), withIntermediateDirectories: true)
        #expect(paths.existingMusicFolders() == (0..<14).map { String(format: "F%02d", $0) })

        let source = root.appendingPathComponent("source.mp3")
        try Data(repeating: 1, count: 512).write(to: source)
        for _ in 0..<40 {
            let placement = try FileReplacement.place(source, in: paths)
            let folder = try #require(FileReplacement.directory(of: placement.relativePath))
            #expect(paths.existingMusicFolders().contains(folder))
            try FileManager.default.removeItem(at: placement.url)
        }
    }

    @Test("an empty file rejected; the folder from the current path")
    func guards() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("place2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IPodPaths(mountPoint: root)
        try FileManager.default.createDirectory(at: paths.musicDirectory, withIntermediateDirectories: true)
        let empty = root.appendingPathComponent("empty.m4a")
        try Data().write(to: empty)
        #expect(throws: (any Error).self) { try FileReplacement.place(empty, in: paths) }

        #expect(FileReplacement.directory(of: "iPod_Control/Music/F30/FPLC.wav") == "F30")
        #expect(FileReplacement.directory(of: "iPod_Control/Music/FPLC.wav") == nil)
        #expect(FileReplacement.directory(of: nil) == nil)
    }

    @Test("the record after the replacement points to the new file and carries its parameters")
    func record() throws {
        let data = LibraryFixture.database(
            tracks: [.init(id: 1, title: "A", album: "X", artist: "Q", number: 1)],
            albumOrder: [0], jump: [(65, 0, 1)])
        let library = try ITunesDBParser.parse(data)
        let track = try #require(library.tracks.first)
        let updated = track.replacingFile(relativePath: "iPod_Control/Music/F19/ABCD.m4a", sizeBytes: 15_137_550,
                                          durationMilliseconds: 156_176, bitRate: 775, sampleRate: 44_100,
                                          kind: .appleLossless)
        #expect(updated.uniqueID == track.uniqueID)
        #expect(updated.persistentID == track.persistentID)
        #expect(updated.fields[.location] == ":iPod_Control:Music:F19:ABCD.m4a")
        #expect(updated.relativePath == "iPod_Control/Music/F19/ABCD.m4a")
        #expect(updated.fields[.fileType] == "Apple Lossless audio file")
        #expect(updated.sizeBytes == 15_137_550)
        #expect(updated.durationMilliseconds == 156_176)
        #expect(updated.rawSampleRate >> 16 == 44_100)
        if updated.rawHeader.count >= 0x130 {
            #expect(updated.sizeBytesSecondary == 15_137_550)
            #expect(updated.sampleRateFloat == 44_100)
        }
    }
}
