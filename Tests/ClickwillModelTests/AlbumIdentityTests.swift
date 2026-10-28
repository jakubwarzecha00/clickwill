import Foundation
import Testing
import ITDBKit
@testable import ClickwillModel

/// Album card identity across edits. The synthetic database: Aftermath (Rolling
/// Stones), The Bends (Radiohead), Currents (Tame Impala).
@Suite("Album identity")
@MainActor
struct AlbumIdentityTests {

    private func model() async throws -> (LibraryModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)", isDirectory: true)
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let model = LibraryModel()
        await model.load(.snapshot(root))
        return (model, root)
    }

    private func titles(_ model: LibraryModel, _ card: AlbumCard) -> [String] { model.tracks(of: card).map(\.title) }

    @Test("renaming and moving an album do not change its identifier")
    func renameAndMoveKeepID() async throws {
        let (model, root) = try await model(); defer { try? FileManager.default.removeItem(at: root) }
        let ids = model.albums.map(\.id)
        let currents = try #require(model.albums.first { $0.title == "Currents" })

        try model.setAlbumField(currents, .title, to: "Currents (Deluxe)")
        #expect(model.albums.map(\.id) == ids)
        #expect(model.current(currents)?.title == "Currents (Deluxe)")

        let library = try #require(model.library)
        model.replaceLibrary(try library.movingAlbum("Currents (Deluxe)", .before("Aftermath")))
        model.rebuildCards()
        #expect(Set(model.albums.map(\.id)) == Set(ids))
        #expect(model.albums.first?.id == currents.id)
    }

    /// The risk with the old identifiers ("title#block"): after a rename the card
    /// from the view had no counterpart, and the model took its old track positions -
    /// after removing a track from an album before it, they pointed to other tracks.
    @Test("a card from before a rename and an earlier removal: the right tracks")
    func staleCardAfterRenameAndShift() async throws {
        let (model, root) = try await model(); defer { try? FileManager.default.removeItem(at: root) }
        let currents = try #require(model.albums.first { $0.title == "Currents" })
        let expected = titles(model, currents)

        try model.setAlbumField(currents, .title, to: "Currents (Deluxe)")
        let aftermath = try #require(model.albums.first { $0.title == "Aftermath" })
        try model.deleteTrack(try #require(model.tracks(of: aftermath).first), in: aftermath)

        #expect(titles(model, currents) == expected, "a card from the view from before both edits")
        model.renameTrack(try #require(model.tracks(of: currents).first), in: currents, to: "New title")
        #expect(model.library?.tracks.first { $0.title == "New title" }?.album == "Currents (Deluxe)")
    }

    @Test("a removed anchor track: the card finds itself by the remaining tracks")
    func anchorDeleted() async throws {
        let (model, root) = try await model(); defer { try? FileManager.default.removeItem(at: root) }
        let bends = try #require(model.albums.first { $0.title == "The Bends" })
        let anchorID: UInt64 = { if case .album(let anchor) = bends.id { return anchor } else { return 0 } }()
        let anchor = try #require(model.tracks(of: bends).first { $0.persistentID == anchorID })

        try model.deleteTrack(anchor, in: bends)

        let now = try #require(model.current(bends))
        #expect(now.id != bends.id)
        #expect(now.title == "The Bends")
        #expect(model.tracks(of: bends).count == 2)
    }

    @Test("a removed album: no card and no tracks instead of someone else's; the rest unchanged")
    func albumDeleted() async throws {
        let (model, root) = try await model(); defer { try? FileManager.default.removeItem(at: root) }
        let aftermath = try #require(model.albums.first { $0.title == "Aftermath" })
        let others = model.albums.dropFirst().map(\.id)

        try model.deleteAlbum(aftermath)

        #expect(model.current(aftermath) == nil)
        #expect(model.tracks(of: aftermath).isEmpty)
        #expect(model.albums.map(\.id) == Array(others))
    }

    @Test("merge: the card of the merged album leads to the target album")
    func mergedCardFollows() async throws {
        let (model, root) = try await model(); defer { try? FileManager.default.removeItem(at: root) }
        let library = try #require(model.library)
        model.replaceLibrary(library.mappingTracks { $0.title == "Let Me Down" ? $0.setting(.sortAlbumArtist, to: "Someone Else") : $0 })
        model.rebuildCards()
        let parts = model.coverFlowAlbums.filter { $0.title == "Aftermath" }
        #expect(parts.count == 2)
        let stray = try #require(parts.first { model.tracks(of: $0).contains { $0.title == "Let Me Down" } })
        let target = try #require(parts.first { $0.id != stray.id })

        model.mergeAlbum(stray, into: target)

        #expect(model.coverFlowAlbums.filter { $0.title == "Aftermath" }.count == 1)
        #expect(model.current(stray)?.trackCount == target.trackCount + stray.trackCount)
    }
}
