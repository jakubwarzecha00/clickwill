import Foundation
import Testing
@testable import ITDBKit

/// Redirects when merging duplicates: playlists, the album record and pending
/// plays from `Play Counts` must go to the copy that stays.
@Suite("Redirects when merging duplicates")
struct DuplicateRedirectsTests {

    private func library() throws -> ITLibrary { try LibraryFixture.standard() }

    /// A library with an extra regular playlist with the given items.
    private func withPlaylist(_ ids: [UInt32]) throws -> ITLibrary {
        var library = try library()
        let master = try #require(library.playlists.first { $0.isMaster })
        let template = try #require(master.entries.first)
        let entries = ids.enumerated().map { index, id in
            ITPlaylistEntry(trackID: id, order: UInt32(index), mhods: template.mhods, rawHeader: template.rawHeader)
        }
        let mix = ITPlaylist(name: "Mix", isMaster: false, persistentID: 0x5151, entries: entries,
                             mhods: [], rawHeader: master.rawHeader)
        library.sections = library.sections.map { section in
            guard case .playlists(let playlists) = section.content else { return section }
            var updated = section
            updated.content = .playlists(playlists + [mix])
            return updated
        }
        return library
    }

    private func mix(_ library: ITLibrary) -> [UInt32] {
        library.playlists.first { $0.name == "Mix" }?.entries.map(\.trackID) ?? []
    }

    @Test("the removed copy's item moves to the copy that stays")
    func playlistEntryMoves() throws {
        let redirected = try withPlaylist([10, 14, 11]).redirectingPlaylistEntries([14: 12])
        #expect(mix(redirected) == [10, 12, 11])
        // The master playlist unchanged - only the track removal puts it in order.
        #expect(redirected.playlists.first { $0.isMaster }?.entries.count == 7)
    }

    @Test("a playlist that already has the kept copy does not get it a second time")
    func noSecondCopyInPlaylist() throws {
        let redirected = try withPlaylist([12, 14, 11]).redirectingPlaylistEntries([14: 12])
        #expect(mix(redirected) == [12, 11])
    }

    @Test("after removing the copy the playlist points only to existing tracks")
    func survivesRemoval() throws {
        let result = try withPlaylist([14, 11]).redirectingPlaylistEntries([14: 12]).removingTracks(uniqueIDs: [14])
        #expect(mix(result) == [12, 11])
        #expect(!result.tracks.contains { $0.uniqueID == 14 })
    }

    @Test("the artwork pointer in the album record moves to the copy that stays")
    func albumArtworkOwnerMoves() throws {
        var library = try library()
        library.sections = library.sections.map { section in
            guard case .albums(let albums) = section.content else { return section }
            var updated = section
            updated.content = .albums(albums.map { album in
                var changed = album
                if album.title == "The Bends" { changed.artworkOwnerPersistentID = 0xAAAA }
                return changed
            })
            return updated
        }
        let redirected = library.redirectingAlbumArtworkOwners([0xAAAA: 0xBBBB])
        #expect(redirected.albums.first { $0.title == "The Bends" }?.artworkOwnerPersistentID == 0xBBBB)
        #expect(redirected.albums.first { $0.title == "Aftermath" }?.artworkOwnerPersistentID == 0)
    }

    // MARK: - Play Counts

    private func entry(plays: UInt32, at date: Date? = nil) -> PlayCounts.Entry {
        PlayCounts.Entry(playCount: plays, lastPlayed: date, bookmarkMilliseconds: 0, rating: 0,
                         skipCount: 0, lastSkipped: nil, unknownField: 0)
    }

    private func counts(_ entries: [PlayCounts.Entry]) -> PlayCounts {
        PlayCounts(entries: entries, entryLength: 28, rawHeader: [])
    }

    @Test("pending plays add to the counter from the library, not from disk")
    func addsOnTopOfTheEditedCount() throws {
        let onDisk = try library()
        let index = try #require(onDisk.tracks.firstIndex { $0.uniqueID == 12 })
        var entries = Array(repeating: entry(plays: 0), count: onDisk.tracks.count)
        entries[index] = entry(plays: 2)
        // The merge has already added 5 plays of the removed copy.
        let edited = onDisk.mappingTracks { track in
            var copy = track
            if track.uniqueID == 12 { copy.playCount = track.playCount + 5 }
            return copy
        }
        let base = try #require(onDisk.tracks.first { $0.uniqueID == 12 }).playCount

        let result = PlayCounts.applying(counts(entries), recordedFor: onDisk.tracks, to: edited)
        #expect(result.changed == 1)
        #expect(result.library.tracks.first { $0.uniqueID == 12 }?.playCount == base + 5 + 2)
    }

    @Test("the plays of the removed copy go to the one that stays")
    func redirectsPendingPlays() throws {
        let onDisk = try library()
        let gone = try #require(onDisk.tracks.firstIndex { $0.uniqueID == 14 })
        let kept = try #require(onDisk.tracks.firstIndex { $0.uniqueID == 12 })
        let played = Date(timeIntervalSince1970: 1_790_000_000)
        var entries = Array(repeating: entry(plays: 0), count: onDisk.tracks.count)
        entries[gone] = entry(plays: 3, at: played)
        entries[kept] = entry(plays: 1)
        let outgoing = try onDisk.removingTracks(uniqueIDs: [14])
        let base = onDisk.tracks[kept].playCount

        let result = PlayCounts.applying(counts(entries), recordedFor: onDisk.tracks, to: outgoing, redirects: [14: 12])
        let track = try #require(result.library.tracks.first { $0.uniqueID == 12 })
        #expect(track.playCount == base + 3 + 1)
        #expect(track.lastPlayed == played)
    }

    @Test("without a redirect the plays of a removed track are lost, the rest unchanged")
    func removedWithoutRedirectLosesPlays() throws {
        let onDisk = try library()
        let gone = try #require(onDisk.tracks.firstIndex { $0.uniqueID == 14 })
        var entries = Array(repeating: entry(plays: 0), count: onDisk.tracks.count)
        entries[gone] = entry(plays: 3)
        let outgoing = try onDisk.removingTracks(uniqueIDs: [14])

        let result = PlayCounts.applying(counts(entries), recordedFor: onDisk.tracks, to: outgoing)
        #expect(result.library.tracks.map(\.playCount) == outgoing.tracks.map(\.playCount))
    }
}
