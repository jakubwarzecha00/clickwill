import Foundation
import ITDBKit

/// A movie on the iPod, as the Videos screen lists it. Read only.
public struct VideoRow: Identifiable, Sendable, Hashable {
    /// The track's `uniqueID`.
    public let id: UInt32
    public let title: String
    public let duration: TimeInterval
    public let sizeBytes: Int64
    public let dateAdded: Date?

    public var displayTitle: String { title.isEmpty ? "Untitled Movie" : title }
}

/// The movies of the library, in database order. A plain value rebuilt with the album cards
/// (`LibraryModel.rebuildCards()`); it never changes the library.
public struct VideoCatalog: Sendable {
    public let movies: [VideoRow]
    /// Records that are neither music nor a movie. Their media kinds (TV shows, podcasts and
    /// others) are not measured yet, so no screen claims to know what they are.
    public let unrecognizedCount: Int

    public static let empty = VideoCatalog(movies: [], unrecognizedCount: 0)

    private init(movies: [VideoRow], unrecognizedCount: Int) {
        self.movies = movies
        self.unrecognizedCount = unrecognizedCount
    }

    public init(library: ITLibrary) {
        movies = library.tracks.filter(\.isMovie).map { track in
            VideoRow(id: track.uniqueID, title: track.title ?? "", duration: track.duration,
                     sizeBytes: Int64(track.sizeBytes), dateAdded: track.dateAdded)
        }
        unrecognizedCount = library.tracks.count { !$0.isMusic && !$0.isMovie }
    }
}
