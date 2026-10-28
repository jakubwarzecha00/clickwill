import AVFoundation
import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

@Suite("Import from a folder")
struct AudioImportTests {

    /// A folder with fake files: we check the rules around files, not
    /// audio decoding - the latter has its own tests on real files.
    static func directory(_ names: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-import-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            try Data([0x00]).write(to: root.appendingPathComponent(name))
        }
        return root
    }

    static func candidate(title: String, album: String? = nil, number: UInt32 = 0, file: String) -> AudioImport.Candidate {
        let draft = TrackDraft(title: title, artist: "Slint", albumArtist: "Slint", album: album,
                               trackNumber: number, kind: .mp3, relativePath: "")
        return AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/\(file)"), draft: draft,
                                     verdict: .supported, formatLabel: "MP3", artwork: nil)
    }

    @Test("an album without numbers gets them in file order")
    func numbersFromFileOrder() {
        let numbered = AudioImport.numbered([
            Self.candidate(title: "Breadcrumb Trail", album: "Spiderland", file: "01.mp3"),
            Self.candidate(title: "Nosferatu Man", album: "Spiderland", file: "02.mp3"),
            Self.candidate(title: "Don, Aman", album: "Spiderland", file: "03.mp3"),
        ])
        #expect(numbered.map(\.draft.trackNumber) == [1, 2, 3])
        #expect(numbered.allSatisfy { $0.draft.totalTracks == 3 })
    }

    @Test("an album in which someone already numbered the tracks stays untouched")
    func existingNumbersKept() {
        let numbered = AudioImport.numbered([
            Self.candidate(title: "Breadcrumb Trail", album: "Spiderland", number: 1, file: "a.mp3"),
            Self.candidate(title: "Nosferatu Man", album: "Spiderland", number: 0, file: "b.mp3"),
        ])
        #expect(numbered.map(\.draft.trackNumber) == [1, 0])
    }

    @Test("a single file does not get a number out of thin air")
    func singleFileNotNumbered() {
        let numbered = AudioImport.numbered([Self.candidate(title: "Good Morning, Captain", album: "Spiderland", file: "a.mp3")])
        #expect(numbered[0].draft.trackNumber == 0)
    }

    @Test("artwork recognized by name, in a fixed order of precedence")
    func coverByName() throws {
        let root = try Self.directory(["back.jpg", "folder.jpg", "cover.jpg", "01.mp3"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AudioImport.coverFile(in: root)?.lastPathComponent == "cover.jpg")
    }

    @Test("when there is no known name, but there is one image - that is the artwork")
    func singleImageIsTheCover() throws {
        let root = try Self.directory(["scan001.png", "01.mp3", "notes.txt"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AudioImport.coverFile(in: root)?.lastPathComponent == "scan001.png")
    }

    @Test("several images without a known name are not artwork - we do not guess")
    func ambiguousImagesRefused() throws {
        let root = try Self.directory(["scan001.png", "scan002.png", "01.mp3"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AudioImport.coverFile(in: root) == nil)
    }

    @Test("a folder without an image gives no artwork")
    func noCover() throws {
        let root = try Self.directory(["01.mp3", "02.mp3"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(AudioImport.coverFile(in: root) == nil)
    }

    @Test("artwork source: tags take precedence over a file next to them")
    func embeddedWinsOverFolder() {
        var candidate = Self.candidate(title: "Washer", album: "Spiderland", file: "a.mp3")
        candidate.folderCover = URL(fileURLWithPath: "/tmp/cover.jpg")
        #expect(candidate.coverSource == .file(URL(fileURLWithPath: "/tmp/cover.jpg")))

        let withTags = AudioImport.Candidate(
            url: URL(fileURLWithPath: "/tmp/b.mp3"), draft: candidate.draft, verdict: .supported,
            formatLabel: "MP3", artwork: Data([1, 2, 3]), folderCover: URL(fileURLWithPath: "/tmp/cover.jpg"))
        #expect(withTags.coverSource == .embedded(Data([1, 2, 3])))
    }

    // MARK: - Vorbis tags (FLAC)

    /// A field as AVFoundation gives it from a FLAC file: `vorb/<KEY>`.
    static func vorbis(_ key: String, _ value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataIdentifier(rawValue: "vorb/" + key)
        item.value = value as NSString
        return item
    }

    @Test("FLAC: the album artist from a Vorbis tag, also in the variant with a space and lowercase")
    func vorbisAlbumArtist() async {
        #expect(await AudioImport.vorbisString([Self.vorbis("ALBUMARTIST", "Playboi Carti")], "ALBUMARTIST", "ALBUM ARTIST") == "Playboi Carti")
        #expect(await AudioImport.vorbisString([Self.vorbis("album artist", "Slint")], "ALBUMARTIST", "ALBUM ARTIST") == "Slint")
        #expect(await AudioImport.vorbisString([Self.vorbis("ARTIST", "Slint")], "ALBUMARTIST", "ALBUM ARTIST") == nil)
    }

    @Test("FLAC: the track number as 3/12 or with a separate track count field")
    func vorbisTrackNumber() async {
        let joined = await AudioImport.vorbisPair([Self.vorbis("TRACKNUMBER", "2/24")], "TRACKNUMBER", totals: "TRACKTOTAL", "TOTALTRACKS")
        #expect(joined.0 == 2 && joined.1 == 24)
        let separate = await AudioImport.vorbisPair([Self.vorbis("TRACKNUMBER", "7"), Self.vorbis("TOTALTRACKS", "10")],
                                                    "TRACKNUMBER", totals: "TRACKTOTAL", "TOTALTRACKS")
        #expect(separate.0 == 7 && separate.1 == 10)
        let missing = await AudioImport.vorbisPair([Self.vorbis("DISCNUMBER", "1")], "TRACKNUMBER", totals: "TRACKTOTAL")
        #expect(missing.0 == 0 && missing.1 == 0)
    }
}

@Suite("Expanding folders when adding")
struct ExpandingFoldersTests {
    @Test("a folder with a subfolder: audio files by path, without hidden and non-audio ones; single files unchanged")
    func expands() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("expand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let album = root.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album.appendingPathComponent("CD2"), withIntermediateDirectories: true)
        for name in ["02 B.mp3", "01 A.flac", "artwork.jpg", "._01 A.flac", "CD2/01 C.m4a"] {
            try Data([0]).write(to: album.appendingPathComponent(name))
        }
        let single = root.appendingPathComponent("note.txt")
        try Data([0]).write(to: single)

        // The enumerator gives the path after expanding /var -> /private/var - we compare from the test folder.
        let found = AudioImport.expandingFolders([single, album]).map { url in
            url.pathComponents.drop { $0 != root.lastPathComponent }.dropFirst().joined(separator: "/")
        }
        #expect(found == ["note.txt", "Album/01 A.flac", "Album/02 B.mp3", "Album/CD2/01 C.m4a"])
    }
}
