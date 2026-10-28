import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

@Suite("Detecting tracks that already exist")
struct DuplicateCheckTests {

    static func draft(_ title: String, artist: String? = "Ozzy Osbourne", album: String? = "Ozzmosis",
                      duration: UInt32 = 243_000) -> TrackDraft {
        TrackDraft(title: title, artist: artist, albumArtist: "Ozzy Osbourne", album: album,
                   durationMilliseconds: duration, kind: .appleLossless, relativePath: "")
    }

    @Test("the same song is recognized despite different case, accents and spaces")
    func normalizedMatch() {
        let index = SongIndex(tracks: [], queued: [Self.draft("Perry Mason")])
        #expect(index.place(of: Self.draft("perry  mason ")) == .queued)
        let accents = SongIndex(tracks: [], queued: [Self.draft("Café", album: "Déjà Vu")])
        #expect(accents.place(of: Self.draft("cafe", album: "deja vu")) == .queued)
    }

    @Test("transcoding changes the length by a fraction of a second - it is still the same song")
    func durationTolerance() {
        let index = SongIndex(tracks: [], queued: [Self.draft("Perry Mason", duration: 243_000)])
        #expect(index.place(of: Self.draft("Perry Mason", duration: 244_900)) == .queued)
        #expect(index.place(of: Self.draft("Perry Mason", duration: 250_000)) == nil)
    }

    @Test("the same title on another album is a separate item")
    func otherAlbumIsNotDuplicate() {
        let index = SongIndex(tracks: [], queued: [Self.draft("Perry Mason")])
        #expect(index.place(of: Self.draft("Perry Mason", album: "The Ozzman Cometh")) == nil)
        #expect(index.place(of: Self.draft("Perry Mason", artist: "Someone Else")) == nil)
    }

    @Test("no track artist - we compare by the album artist")
    func fallsBackToAlbumArtist() {
        let index = SongIndex(tracks: [], queued: [Self.draft("Perry Mason")])
        #expect(index.place(of: Self.draft("Perry Mason", artist: nil)) == .queued)
    }

    @Test("a file without a title is not marked")
    func untitledIgnored() {
        let index = SongIndex(tracks: [], queued: [Self.draft("  ")])
        #expect(index.place(of: Self.draft("")) == nil)
    }
}
