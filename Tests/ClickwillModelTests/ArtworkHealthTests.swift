import Testing
import ITDBKit
@testable import ClickwillModel

@Suite("Artwork state for the report")
struct ArtworkHealthTests {

    @Test("without ArtworkDB every album has no artwork; the report counts albums and gives no titles")
    func noArtworkMeansNoCover() throws {
        let library = try ITunesDBParser.parse(SyntheticLibrary.database())
        let titles = Set(library.tracks.map { $0.album ?? "" })
        let health = ArtworkHealth.check(library: library, artwork: nil, artworkDB: nil, paths: nil)
        #expect(health.findings[.noCover]?.count == titles.count)
        let summary = health.summary.joined(separator: "\n")
        #expect(summary.contains("no cover image: \(titles.count) of \(titles.count) album titles"))
        for title in titles where !title.isEmpty { #expect(!summary.contains(title)) }
        let title = try #require(titles.first)
        #expect(health.details(forAlbum: title).contains { $0.contains("no cover image") })
    }
}
