import Testing
import Foundation
@testable import ITDBKit

/// Comparing libraries - the backups screen relies on it, so it must say
/// exactly what changed, and nothing more.
@Suite("Differences between libraries")
struct LibraryDiffTests {

    private func base() throws -> ITLibrary { try LibraryFixture.standard() }

    @Test("the same library has no differences")
    func identical() throws {
        #expect(LibraryDiff(from: try base(), to: try base()).isEmpty)
    }

    @Test("plays are not a change")
    func playCountsIgnored() throws {
        // The iPod counts them itself on every use - showing them would flood
        // every comparison with changes nobody made.
        let played = try base().mappingTracks { track in
            var copy = track; copy.playCount += 5; copy.lastPlayed = Date(); return copy
        }
        #expect(LibraryDiff(from: try base(), to: played).isEmpty)
    }

    @Test("renaming one track is one change with the values before and after")
    func singleTitle() throws {
        let first = try #require(try base().tracks.first)
        let renamed = try base().mappingTracks { track in
            guard track.persistentID == first.persistentID else { return track }
            var copy = track; copy.fields[.title] = "New title"; return copy
        }
        let diff = LibraryDiff(from: try base(), to: renamed)
        #expect(diff.edits.count == 1)
        let edit = try #require(diff.edits.first)
        #expect(edit.field == .title)
        #expect(edit.before == first.title)
        #expect(edit.after == "New title")
    }

    @Test("the same change on a whole album is one item")
    func groupsAlbumWideEdits() throws {
        let album = try #require(try base().tracks.first?.album)
        let count = try base().tracks.count { $0.album == album }
        let edited = try base().mappingTracks { track in
            guard track.album == album else { return track }
            var copy = track; copy.fields[.genre] = "Metal"; return copy
        }
        let changes = try #require(LibraryDiff(from: try base(), to: edited).albums.first { $0.album == album })
        #expect(changes.edits.count == 1, "not \(count) identical lines")
        #expect(changes.edits.first?.songs.count == count)
        #expect(changes.edits.first?.after == "Metal")
    }

    @Test("a track that is gone is removed; a new one is added")
    func addedAndRemoved() throws {
        let first = try #require(try base().tracks.first)
        // The same record under a different identifier: for the comparison it is a different track.
        let swapped = try base().mappingTracks { track in
            guard track.persistentID == first.persistentID else { return track }
            var copy = track; copy.persistentID &+= 0x1_0000_0000; return copy
        }
        let diff = LibraryDiff(from: try base(), to: swapped)
        #expect(diff.removed.map(\.persistentID) == [first.persistentID])
        #expect(diff.added.count == 1)
        #expect(diff.edits.isEmpty)
    }

    @Test("an artwork and file change is visible")
    func coverAndFile() throws {
        let first = try #require(try base().tracks.first)
        let changed = try base().mappingTracks { track in
            guard track.persistentID == first.persistentID else { return track }
            return track.settingArtworkIdentifier(track.artworkIdentifier &+ 7)
        }
        let fields = Set(LibraryDiff(from: try base(), to: changed).edits.map(\.field))
        #expect(fields == [.cover])
    }
}
