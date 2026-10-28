import Foundation
import Testing
@testable import ITDBKit

@Suite("Intended order")
struct OrderIntentTests {

    @Test("a captured intent matches the current table and applying it changes nothing")
    func captureIsIdempotent() throws {
        let library = try LibraryFixture.standard()
        let intent = library.captureOrderIntent()
        #expect(intent.albums == ["Aftermath", "The Bends", "Currents"])
        #expect(intent.tracks["The Bends"]?.count == 3)
        #expect(library.matches(intent))

        let (applied, report) = try library.applyingOrderIntent(intent)
        #expect(!report.changed)
        #expect(applied.browseIndex(.album)?.entries == library.browseIndex(.album)?.entries)
    }

    @Test("the intent restores the order after it was lost")
    func restoresAfterRegeneration() throws {
        let curated = try LibraryFixture.standard()
            .movingAlbum("Currents", .atIndex(0))
            .movingTrack(14, in: "The Bends", .atIndex(0))
        let intent = curated.captureOrderIntent()

        // "Regeneration": we go back to the alphabetical layout from the fixture.
        let regenerated = try LibraryFixture.standard()
        #expect(!regenerated.matches(intent))

        let (restored, report) = try regenerated.applyingOrderIntent(intent)
        #expect(report.changed)
        #expect(restored.albumOrder().map(\.album) == ["Currents", "Aftermath", "The Bends"])
        #expect(try restored.trackOrder(album: "The Bends").map(\.title) == ["Just", "Planet Telex", "Bones"])
        #expect(restored.matches(intent))
        #expect(restored.browseIndex(.album)?.entries == curated.browseIndex(.album)?.entries)
    }

    @Test("new albums and tracks go to the end, missing ones are skipped")
    func handlesDrift() throws {
        var intent = try LibraryFixture.standard().captureOrderIntent()
        intent.albums = ["Currents", "Missing", "Aftermath"]        // no The Bends, there is a ghost
        intent.tracks["Aftermath"] = [0x1000 + 13, 0x1000 + 99]      // one real, one ghost

        let (applied, report) = try LibraryFixture.standard().applyingOrderIntent(intent)
        #expect(applied.albumOrder().map(\.album) == ["Currents", "Aftermath", "The Bends"])
        #expect(report.missingAlbums == ["Missing"])
        #expect(report.newAlbums == ["The Bends"])
        #expect(report.missingTracks == 1)
        #expect(report.newTracks == 1)
        #expect(try applied.trackOrder(album: "Aftermath").map(\.uniqueID) == [13, 11])
    }

    @Test("the intent goes through JSON without loss")
    func jsonRoundTrip() throws {
        let intent = try LibraryFixture.standard().movingAlbum("Currents", .atIndex(0)).captureOrderIntent(jumpTable: .flat)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-intent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = OrderIntentStore(root: dir)

        #expect(try store.load(deviceGUID: "ABC") == nil)
        try store.save(intent, deviceGUID: "ABC")
        let loaded = try #require(try store.load(deviceGUID: "ABC"))
        #expect(loaded.albums == intent.albums)
        #expect(loaded.tracks == intent.tracks)
        #expect(loaded.jumpTable == .flat)
        #expect(abs(loaded.capturedAt.timeIntervalSince(intent.capturedAt)) < 1)
    }
}
