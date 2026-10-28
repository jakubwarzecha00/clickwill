import Foundation
import Testing
@testable import ITDBKit

@Suite("Originals archive")
struct OriginalArchiveTests {

    @Test("the file name from metadata, without characters that break a path")
    func names() {
        #expect(OriginalArchive.fileName(artist: "Travis Scott", album: "JACKBOYS 2", trackNumber: 18, title: "Da Wizard", fileExtension: "m4a")
                == "Travis Scott - JACKBOYS 2 - 18 Da Wizard.m4a")
        #expect(OriginalArchive.fileName(artist: "AC/DC", album: nil, trackNumber: 0, title: "T:N:T", fileExtension: "WAV")
                == "AC-DC - T-N-T.wav")
        #expect(OriginalArchive.fileName(artist: nil, album: nil, trackNumber: 0, title: nil, fileExtension: "mp3")
                == "Untitled.mp3")
    }

    @Test("the copy goes to the folder, collisions do not overwrite")
    func store() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("arch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("src-\(UUID().uuidString).wav")
        try Data(repeating: 3, count: 4096).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let archive = root.appendingPathComponent("Originals", isDirectory: true)   // does not exist
        let first = try OriginalArchive.store(source, in: archive, as: "A - B - 01 C.wav")
        #expect(first.sizeBytes == 4096)
        #expect(first.url.lastPathComponent == "A - B - 01 C.wav")
        let second = try OriginalArchive.store(source, in: archive, as: "A - B - 01 C.wav")
        #expect(second.url.lastPathComponent == "A - B - 01 C (2).wav")
        let contents = try FileManager.default.contentsOfDirectory(atPath: archive.path)
        #expect(contents.count == 2)
    }

    @Test("a file instead of a folder - a refusal, nothing is lost")
    func refusesFileAsDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("arch2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let notADirectory = root.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: notADirectory)
        let source = root.appendingPathComponent("s.wav")
        try Data(repeating: 1, count: 16).write(to: source)
        #expect(throws: (any Error).self) { try OriginalArchive.store(source, in: notADirectory, as: "x.wav") }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}
