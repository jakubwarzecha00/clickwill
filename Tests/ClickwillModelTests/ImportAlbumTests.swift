import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

@Suite("Albums in the add sheet")
struct ImportAlbumTests {

    private func song(_ title: String, disc: UInt32 = 1, number: UInt32 = 0) -> AudioImport.Candidate {
        var draft = TrackDraft(title: title, artist: "A", albumArtist: "A", album: "X", sizeBytes: 1, kind: .mp3, relativePath: "")
        draft.discNumber = disc
        draft.trackNumber = number
        return AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/\(title).mp3"), draft: draft, verdict: .supported,
                                     formatLabel: "MP3", artwork: nil)
    }

    @Test("groups in file order; within a group disc, number, and without numbers file order")
    func grouping() {
        let a3 = song("a3", number: 3), a1 = song("a1", number: 1), b = song("b"), a2d2 = song("a2d2", disc: 2, number: 1)
        let c1 = song("c1"), c2 = song("c2")
        let groupOf = [a1.id: a3.id, a2d2.id: a3.id, c2.id: c1.id]

        let albums = ImportAlbum.grouping([a3, b, a1, c1, a2d2, c2], groupOf: groupOf)

        #expect(albums.map(\.id) == [a3.id, b.id, c1.id])
        #expect(albums[0].songs.map(\.draft.title) == ["a1", "a3", "a2d2"])
        #expect(albums[1].songs.map(\.draft.title) == ["b"])
        #expect(albums[2].songs.map(\.draft.title) == ["c1", "c2"], "without numbers - file order")
    }

    @Test("an empty list - no albums")
    func empty() {
        #expect(ImportAlbum.grouping([], groupOf: [:]).isEmpty)
    }
}
