import Foundation
import ITDBKit

/// What is going on with an album on the iPod - for the column next to the Albums wheel. Data only;
/// the app builds the sentences.
public struct AlbumFacts: Sendable, Equatable {
    /// The file format, when all files share one: the label from the format scan,
    /// and before it, a guess from the extension. `nil` - albums in several formats.
    public let format: String?
    /// Total on the iPod; for an album from the queue - the size of the files on the Mac.
    public let bytes: Int64
    /// Tracks the iPod will not play (the format scan verdict).
    public let unplayable: Int
    /// An album from the queue: what the write will convert the files to, when needed.
    public let convertsTo: String?
}

extension LibraryModel {

    public func facts(of album: AlbumCard) -> AlbumFacts {
        if case .pending = album.id, let pending = pendingAlbum(id: album.id) {
            let targets = Set(pending.additions.compactMap { addition -> String? in
                if case .convertible(_, let target) = addition.verdict { return target.label }
                return nil
            })
            return AlbumFacts(format: Self.single(pending.additions.map(\.formatLabel)),
                              bytes: pending.additions.reduce(0) { $0 + Int64($1.draft.sizeBytes) },
                              unplayable: 0,
                              convertsTo: targets.count == 1 ? targets.first : nil)
        }
        guard let library else { return AlbumFacts(format: nil, bytes: 0, unplayable: 0, convertsTo: nil) }
        let tracks = album.trackIndices.compactMap { $0 < library.tracks.count ? library.tracks[$0] : nil }
        return AlbumFacts(
            format: Self.single(tracks.map { formatLabels[$0.uniqueID] ?? Self.formatGuess($0) }),
            bytes: tracks.reduce(0) { $0 + Int64($1.sizeBytes) },
            unplayable: tracks.filter { formatVerdicts[$0.uniqueID].map { !$0.isSupported } ?? false }.count,
            convertsTo: nil)
    }

    /// One value, when all are the same.
    private static func single(_ values: [String]) -> String? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}
