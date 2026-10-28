import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

@Suite("Recognizing an album that is already on the iPod")
struct AlbumMatchingTests {
    static let album = AlbumCard(id: .album(1), trackIndices: [0, 1, 2], trackIDs: [1, 2, 3], title: "The Ultimate Sin",
                                 artist: "Ozzy Osbourne", year: nil, genre: nil, trackCount: 3, duration: 0,
                                 artworkTrackID: nil, missingFiles: 0, isCompilation: false, artistSortKey: "ozzy")

    static func row(_ id: UInt32, _ title: String, _ seconds: TimeInterval, number: UInt32) -> TrackRow {
        TrackRow(id: id, persistentID: UInt64(id), title: title, artist: "Ozzy Osbourne",
                 number: number, duration: seconds, playCount: 3, fileMissing: false)
    }

    static func file(_ title: String, _ milliseconds: UInt32, number: UInt32 = 0) -> AudioImport.Candidate {
        // Like AIFF from a CD: the album is the folder name, no artist.
        let draft = TrackDraft(title: title, artist: nil, albumArtist: nil, album: "The ultimate sin - ozzy osbourne",
                               trackNumber: number, durationMilliseconds: milliseconds, sizeBytes: 1, kind: .wav,
                               relativePath: "")
        return AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/\(title).aiff"), draft: draft, verdict: .supported,
                                     formatLabel: "AIFF", artwork: nil)
    }

    static let rows = [row(1, "The Ultimate Sin", 225.4, number: 1),
                       row(2, "Secret Loser", 248.9, number: 2),
                       row(3, "Never Know Why", 267.1, number: 3)]

    @Test("files without tags match an album by titles and lengths")
    func untaggedFilesMatch() {
        let files = [Self.file("The Ultimate Sin", 225_900), Self.file("Secret Loser", 249_500), Self.file("never know why", 266_800)]
        let match = LibraryModel.pair(files, with: Self.rows, album: Self.album)
        #expect(match.pairs.count == 3)
        #expect(match.isComplete)
        #expect(match.pairs[files[1].id]?.id == 2)
    }

    @Test("a note in brackets and punctuation do not get in the way")
    func bracketsAndPunctuation() {
        #expect(!LibraryModel.titleKeys("Walkin' The Dog [Live]").isDisjoint(with: LibraryModel.titleKeys("Walkin The Dog")))
        #expect(!LibraryModel.titleKeys("Beyoncé").isDisjoint(with: LibraryModel.titleKeys("BEYONCE")))
    }

    @Test("a different length is a different song, even with the same title")
    func durationMatters() {
        let files = [Self.file("The Ultimate Sin", 300_000)]
        let match = LibraryModel.pair(files, with: Self.rows, album: Self.album)
        #expect(match.pairs.isEmpty)
    }

    @Test("a file without a title pairs by track number and length")
    func numberFallback() {
        let files = [Self.file("Track 02", 249_300, number: 2)]
        let match = LibraryModel.pair(files, with: Self.rows, album: Self.album)
        #expect(match.pairs[files[0].id]?.id == 2)
        #expect(match.missingRows.map(\.id) == [1, 3])
        #expect(!match.isComplete)
    }

    @Test("an extra file without a counterpart is listed separately")
    func extraFile() {
        let files = [Self.file("The Ultimate Sin", 225_400), Self.file("Bonus Track", 180_000)]
        let match = LibraryModel.pair(files, with: Self.rows, album: Self.album)
        #expect(match.extraCandidates == [files[1].id])
    }
}
