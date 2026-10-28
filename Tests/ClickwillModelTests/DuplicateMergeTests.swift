import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

@Suite("Merging duplicates")
@MainActor
struct DuplicateMergeTests {

    /// A synthetic library in which "Just" (14) is a second copy of "Planet Telex" (12).
    private func loaded(_ change: (inout ITTrack) -> Void = { _ in }) async throws -> (LibraryModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-test-\(UUID().uuidString)", isDirectory: true)
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let model = LibraryModel()
        await model.load(.snapshot(root))
        let library = try #require(model.library)
        model.replaceLibrary(library.mappingTracks { track in
            var copy = track
            if track.uniqueID == 14 { copy.fields[.title] = "Planet Telex" }
            change(&copy)
            return copy
        })
        model.rebuildCards()
        return (model, root)
    }

    @Test("two copies of the same song are one group; the one with more plays stays")
    func findsTheGroup() async throws {
        let (model, root) = try await loaded { track in
            if track.uniqueID == 12 { track.playCount = 2 }
            if track.uniqueID == 14 { track.playCount = 5 }
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let groups = model.duplicateGroups()
        #expect(groups.count == 1)
        #expect(groups.first?.keep.id == 14)
        #expect(groups.first?.remove.map(\.id) == [12])
        #expect(groups.first?.title == "Planet Telex")
    }

    @Test("a merge adds up plays, takes the higher rating and leaves one log entry")
    func mergeKeepsTheHistory() async throws {
        let (model, root) = try await loaded { track in
            if track.uniqueID == 12 { track.playCount = 2; track.rating = 80 }
            if track.uniqueID == 14 { track.playCount = 5; track.rating = 20 }
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let before = model.trackCount

        let removed = try model.mergeDuplicates(model.duplicateGroups())
        #expect(removed == 1)
        #expect(model.trackCount == before - 1)
        let kept = try #require(model.library?.tracks.first { $0.uniqueID == 14 })
        #expect(kept.playCount == 7)
        #expect(kept.rating == 80)
        #expect(model.library?.tracks.contains { $0.uniqueID == 12 } == false)
        #expect(model.duplicateGroups().isEmpty)
        #expect(model.changes.playCountRedirects == [12: 14])

        let merges = model.changes.log.filter { if case .duplicatesMerged = $0.kind { return true } else { return false } }
        #expect(merges.count == 1)
        #expect(merges.first?.isDestructive == true)
    }

    @Test("discarding the changes restores both copies and clears the redirects")
    func discardRestoresBoth() async throws {
        let (model, root) = try await loaded()
        defer { try? FileManager.default.removeItem(at: root) }
        try model.mergeDuplicates(model.duplicateGroups())
        await model.discardChanges()
        #expect(model.changes.playCountRedirects.isEmpty)
        #expect(model.changes.artworkOwnerRedirects.isEmpty)
        #expect(model.changes.log.isEmpty)
    }

    // MARK: - Rule

    private func tracks(_ change: (inout ITTrack) -> Void) throws -> [ITTrack] {
        try ITunesDBParser.parse(SyntheticLibrary.database()).mappingTracks { track in
            var copy = track
            if track.uniqueID == 14 { copy.fields[.title] = "Planet Telex" }
            change(&copy)
            return copy
        }.tracks
    }

    @Test("a copy with a file wins over a copy without a file, even with fewer plays")
    func fileBeatsPlays() throws {
        let all = try tracks { if $0.uniqueID == 14 { $0.playCount = 50 } }
        let clusters = LibraryModel.duplicateClusters(all, missing: [14], unsupported: [])
        #expect(clusters.first?.map(\.uniqueID) == [12, 14])
    }

    @Test("a higher bitrate wins over the play count")
    func qualityBeatsPlays() throws {
        let all = try tracks { track in
            if track.uniqueID == 12 { track.bitRate = 1_411 }
            if track.uniqueID == 14 { track.bitRate = 320; track.playCount = 50 }
        }
        let clusters = LibraryModel.duplicateClusters(all, missing: [], unsupported: [])
        #expect(clusters.first?.first?.uniqueID == 12)
    }

    @Test("M4A described as AAC or Apple Lossless by bitrate")
    func m4aFormatGuess() throws {
        var track = try #require(try tracks { _ in }.first)
        track.fields[.location] = ":iPod_Control:Music:F00:A.m4a"
        track.bitRate = 256
        #expect(LibraryModel.formatGuess(track) == "AAC 256 kbps")
        track.bitRate = 774
        #expect(LibraryModel.formatGuess(track) == "Apple Lossless 774 kbps")
    }

    @Test("different lengths or different albums are not duplicates")
    func differentSongsStayApart() throws {
        let longer = try tracks { if $0.uniqueID == 14 { $0.durationMilliseconds += 5_000 } }
        #expect(LibraryModel.duplicateClusters(longer, missing: [], unsupported: []).isEmpty)

        let otherAlbum = try tracks { if $0.uniqueID == 14 { $0.fields[.album] = "OK Computer" } }
        #expect(LibraryModel.duplicateClusters(otherAlbum, missing: [], unsupported: []).isEmpty)
    }
}
