import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Artwork in the app's memory: decoded at the view's request, kept until
/// the next library load.
@Suite("Artwork in memory")
@MainActor
struct CoverImagesTests {

    /// A bug from released versions: after Discard All Cover Flow showed placeholders
    /// and never loaded them again. A view asks for artwork once per track
    /// identifier (`.task(id:)`), and a reload from the same source does not change
    /// the identifiers - the second request never came.
    @Test("after discarding changes the artwork comes back without a new request from the view")
    func coversReturnAfterDiscard() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(cover: true)); defer { rig.cleanUp() }
        let aftermath = try rig.album("Aftermath")
        let id = try #require(aftermath.artworkTrackID)
        await rig.model.ensureArtwork(for: id)
        let original = try #require(rig.model.artwork(for: id))

        try rig.model.setArtwork(for: aftermath, image: try WriteTests.image(red: 0, green: 1, blue: 0))
        #expect(rig.model.artwork(for: id) !== original, "a preview of the new artwork")

        await rig.model.discardChanges()
        await rig.model.covers.refresh?.value

        let restored = try #require(rig.model.artwork(for: id), "the artwork comes back by itself")
        #expect(Self.pixel(of: restored) == Self.pixel(of: original), "the artwork from the iPod, not a preview of the discarded change")
    }

    @Test("another source: old requests are not decoded again")
    func otherSourceStartsEmpty() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(cover: true)); defer { rig.cleanUp() }
        let id = try #require(try rig.album("Aftermath").artworkTrackID)
        let covers = CoverImages()
        await covers.reload(paths: rig.paths, artwork: rig.model.artwork, keepRequested: false)
        await covers.ensure(id)
        #expect(covers.image(for: id) != nil)

        await covers.reload(paths: rig.paths, artwork: rig.model.artwork, keepRequested: false)
        await covers.refresh?.value
        #expect(covers.image(for: id) == nil)

        await covers.ensure(id)
        await covers.reload(paths: rig.paths, artwork: rig.model.artwork, keepRequested: true)
        await covers.refresh?.value
        #expect(covers.image(for: id) != nil)
    }

    @Test("a disconnected iPod takes the artwork with it")
    func disconnectClears() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(cover: true)); defer { rig.cleanUp() }
        let id = try #require(try rig.album("Aftermath").artworkTrackID)
        await rig.model.ensureArtwork(for: id)
        #expect(rig.model.artwork(for: id) != nil)

        try FileManager.default.removeItem(at: rig.paths.control)
        #expect(rig.model.deviceDisconnected())
        #expect(rig.model.artwork(for: id) == nil)
    }

    @Test("a new album from the queue shows artwork from the file before it reaches the iPod")
    func pendingAlbumCover() async throws {
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try WriteTests.image(red: 0, green: 0, blue: 1), nil)
        #expect(CGImageDestinationFinalize(destination))
        let draft = TrackDraft(title: "Only Shallow", artist: "My Bloody Valentine", albumArtist: "My Bloody Valentine",
                               album: "Loveless", sizeBytes: 4_000_000, kind: .mp3, relativePath: "")
        let model = try await AdditionsTests.model()
        model.queueAdditions([AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/1.mp3"), draft: draft, verdict: .supported,
                                                    formatLabel: "MP3", artwork: png as Data)])

        let card = try #require(model.pendingAlbums.first?.card)
        let image = try #require(model.artwork(for: card.artworkTrackID))
        #expect(Self.pixel(of: image)[2] > 200, "blue artwork from the file")
    }

    /// The color of the middle pixel.
    nonisolated static func pixel(of image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                        width: CGFloat(image.width), height: CGFloat(image.height)))
        return data
    }
}
