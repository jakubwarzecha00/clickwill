import Testing
import Foundation
@testable import ClickwillModel

/// Matching files to entries that have no file. A mistake in that direction is
/// silent - a file put under the wrong track looks completely
/// normal on the device - so the comparison key has its own tests here.
@Suite("Restoring files")
struct FileImportTests {

    @Test("a featured artist does not break matching")
    func guestCredits() {
        #expect(LibraryModel.matchKey("Zoom (Ft. Gunna)") == LibraryModel.matchKey("Zoom feat. Gunna"))
        #expect(LibraryModel.matchKey("Zoom (Ft. Gunna)") == LibraryModel.matchKey("Zoom featuring Gunna"))
    }

    @Test("punctuation, case and diacritics do not matter")
    func normalisation() {
        #expect(LibraryModel.matchKey("TARS ON THE ROOF") == LibraryModel.matchKey("Tars on the Roof"))
        #expect(LibraryModel.matchKey("Café Ñandú") == LibraryModel.matchKey("cafe  nandu!"))
    }

    @Test("a word is not lost because it contains 'ft'")
    func doesNotEatWords() {
        // The version that cut the character run alone turned this into "aermath".
        #expect(LibraryModel.matchKey("Aftermath") == "aftermath")
        #expect(LibraryModel.matchKey("Aftermath") != LibraryModel.matchKey("Aermath"))
    }

    @Test("different titles stay different")
    func keepsDistinct() {
        #expect(LibraryModel.matchKey("First Class") != LibraryModel.matchKey("Lay Up"))
        #expect(LibraryModel.matchKey("License") != LibraryModel.matchKey("Licenses"))
    }
}

/// Replacing the file of a track that already has one. We guard two promises:
/// that replacing and restoring are described as different things - because only one
/// of them deletes something from the iPod - and that a snapshot without files refuses the replacement,
/// instead of losing the old file.
@Suite("Replacing a file")
@MainActor
struct FileReplacementTests {

    private func snapshot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-replace-\(UUID().uuidString)", isDirectory: true)
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        return root
    }

    private func job(_ id: UInt32, album: String, replacing: URL?) -> PendingFileImport {
        var job = PendingFileImport(
            id: id, album: album, title: "t\(id)", source: URL(fileURLWithPath: "/tmp/new-\(id).mp3"),
            verdict: .supported, formatLabel: "MP3", durationMilliseconds: 1000,
            bitRate: 320, sampleRate: 44_100, kind: .mp3)
        job.replacing = replacing
        return job
    }

    @Test("restoring and replacing are two separate items in the queue")
    func separatePendingEntries() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))

        model.changes.queueFileImport(job(1, album: "A", replacing: nil))
        model.changes.queueFileImport(job(2, album: "A", replacing: URL(fileURLWithPath: "/Volumes/iPod/iPod_Control/Music/F00/OLD.mp3")))
        model.changes.queueFileImport(job(3, album: "B", replacing: URL(fileURLWithPath: "/Volumes/iPod/iPod_Control/Music/F01/OLD.mp3")))

        let kinds = model.changes.log.map(\.kind)
        #expect(kinds.contains { if case .filesRestored(1, 1, 0) = $0 { true } else { false } })
        #expect(kinds.contains { if case .filesReplaced(2, 2, 0) = $0 { true } else { false } },
                "a replacement deletes the old file - it must not pretend to be a restore")
    }

    @Test("emptying the queue removes both items")
    func cancellingClearsBoth() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        model.changes.queueFileImport(job(2, album: "A", replacing: URL(fileURLWithPath: "/x/OLD.mp3")))
        model.cancelFileImport(2)
        #expect(!model.changes.log.contains { if case .filesReplaced = $0.kind { true } else { false } })
    }

    @Test("a snapshot without files refuses the replacement, instead of losing the old file")
    func refusesWithoutCurrentFile() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let album = try #require(model.albums.first)
        let row = try #require(model.tracks(of: album).first { !$0.fileMissing })
        let candidate = ImportCandidate(
            url: URL(fileURLWithPath: "/tmp/elsewhere.mp3"), verdict: .supported, formatLabel: "MP3",
            durationMilliseconds: 1000, taggedTitle: "", trackNumber: 1, sizeBytes: 100,
            bitRate: 320, sampleRate: 44_100, kind: .mp3)

        #expect(throws: FileImportError.self) { try model.replaceFile(candidate, for: row, in: album) }
        #expect(model.changes.fileImports.isEmpty, "the refusal queues nothing")
    }
}
