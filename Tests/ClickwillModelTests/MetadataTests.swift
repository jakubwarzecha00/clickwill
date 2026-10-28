import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

private func snapshot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("clickwill-meta-\(UUID().uuidString)", isDirectory: true)
    let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
    try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
    try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
    return root
}

@Suite("Metadata editing")
@MainActor
struct MetadataTests {

    @Test("track title and number, renumbering an album")
    func trackEdits() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let bends = try #require(model.albums.first { $0.title == "The Bends" })
        let just = try #require(model.tracks(of: bends).first { $0.title == "Just" })

        model.renameTrack(just, in: bends, to: "  Just (remaster) ")
        #expect(model.tracks(of: bends).map(\.title).contains("Just (remaster)"))
        model.renameTrack(just, in: bends, to: "   ")   // empty - no change
        #expect(model.changes.log.count == 1)

        model.setTrackNumber(just, in: bends, to: 9)
        #expect(model.tracks(of: bends).first { $0.id == just.id }?.number == 9)
        // A missing number is an empty value - how to phrase it is up to the app.
        guard case .trackEdited(_, _, "track number", _, "9")? = model.changes.log.last?.kind else {
            Issue.record("\(String(describing: model.changes.log.last?.kind))"); return
        }

        let renumbered = try #require(model.tracks(of: bends).first { $0.id == just.id })
        model.setTrackNumber(renumbered, in: bends, to: 0)
        guard case .trackEdited(_, _, "track number", "9", "")? = model.changes.log.last?.kind else {
            Issue.record("\(String(describing: model.changes.log.last?.kind))"); return
        }

        try model.renumberTracks(in: bends)
        #expect(model.tracks(of: bends).map(\.number) == [1, 2, 3])
        #expect(model.changes.log.count == 4)
        // The tables are still permutations - otherwise the writer would refuse.
        let library = try #require(model.library)
        let index = try #require(library.browseIndex(.album))
        #expect(index.isPermutation(of: library.tracks.count))
    }

    @Test("album fields go to all tracks; a rename returns a new card")
    func albumEdits() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        var card = try #require(model.albums.first { $0.title == "Currents" })

        card = try model.setAlbumField(card, .genre, to: "Psych")
        #expect(model.library?.tracks.filter { $0.album == "Currents" }.allSatisfy { $0.genre == "Psych" } == true)
        card = try model.setAlbumField(card, .year, to: "2015")
        #expect(card.year == 2015)
        #expect(throws: MetadataError.self) { try model.setAlbumField(card, .year, to: "abc") }

        let renamed = try model.setAlbumField(card, .title, to: "Currents (Deluxe)")
        #expect(renamed.title == "Currents (Deluxe)")
        #expect(model.current(renamed) != nil)
        #expect(model.tracks(of: renamed).count == 2)
        #expect(model.albums.contains { $0.title == "Currents" } == false)

        let byArtist = try model.setAlbumField(renamed, .albumArtist, to: "Kevin Parker")
        #expect(byArtist.artist == "Kevin Parker")
        #expect(model.changes.log.count == 4)
    }
}

@Suite("Merging a split album")
@MainActor
struct MergeAlbumTests {
    @Test("a track with a different album artist goes back to the album")
    func merge() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let library = try #require(model.library)
        // The rest of the album has a sort field, the stray track - a different album artist and no field.
        model.replaceLibrary(library.mappingTracks { track in
            guard track.album == "The Bends" else { return track }
            return track.title == "Just" ? track.setting(.albumArtist, to: "Someone Else") : track.setting(.sortAlbumArtist, to: "Radiohead, The")
        })
        model.rebuildCards()
        let cards = model.coverFlowAlbums.filter { $0.title == "The Bends" }
        #expect(cards.count == 2)
        let stray = try #require(cards.first { $0.trackCount == 1 })
        let target = try #require(cards.first { $0.trackCount == 2 })
        #expect(model.splitSiblings(of: stray).map(\.id) == [target.id])

        let merged = model.mergeAlbum(stray, into: target)
        #expect(merged.trackCount == 3)
        #expect(model.coverFlowAlbums.filter { $0.title == "The Bends" }.count == 1)
        #expect(model.library?.tracks.first { $0.title == "Just" }?.albumArtist == nil)
        #expect(model.library?.tracks.first { $0.title == "Just" }?.sortAlbumArtist == "Radiohead, The")
        guard case .albumMerged(_, _, let tracks)? = model.changes.log.last?.kind else {
            Issue.record("change: \(String(describing: model.changes.log.last?.kind))"); return
        }
        #expect(tracks == 1)
    }
}

@Suite("Conversion queue")
@MainActor
struct ConversionQueueTests {

    @Test("without a scan, and for a supported track, a conversion cannot be queued")
    func guards() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let album = try #require(model.albums.first)
        let row = try #require(model.tracks(of: album).first)
        #expect(row.unplayable == false)
        #expect(throws: ConversionQueueError.self) { try model.convertTrack(row, in: album, keepOriginalsIn: nil) }

        // The file exists, but the verdict says "supported" - still a refusal.
        model.formatVerdicts[row.id] = .supported
        #expect(throws: ConversionQueueError.self) { try model.convertTrack(row, in: album, keepOriginalsIn: nil) }
    }

    @Test("the verdict reaches the row and the album card")
    func verdictsReachRows() async throws {
        let root = try snapshot(); defer { try? FileManager.default.removeItem(at: root) }
        let model = LibraryModel(); await model.load(.snapshot(root))
        let album = try #require(model.albums.first)
        let row = try #require(model.tracks(of: album).first)

        model.formatVerdicts[row.id] = .convertible(reason: "24-bit Apple Lossless; the iPod plays 16-bit up to 48 kHz",
                                                    target: .appleLossless(sampleRate: 48_000))
        model.formatLabels[row.id] = "ALAC 24-bit 48 kHz"
        model.rebuildCards()

        let refreshed = try #require(model.tracks(of: album).first { $0.id == row.id })
        #expect(refreshed.unplayable)
        #expect(refreshed.formatLabel == "ALAC 24-bit 48 kHz")
    }
}
