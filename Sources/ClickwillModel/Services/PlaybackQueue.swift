/// A queue without looping. A missing next or previous track does not change the index.
public struct PlaybackQueue: Sendable {
    public let tracks: [TrackRow]
    public private(set) var currentIndex: Int?

    public var currentTrack: TrackRow? { currentIndex.map { tracks[$0] } }

    /// A missing starting track moves the start to the next available track.
    public init(_ tracks: [TrackRow], startingAt: TrackRow? = nil) {
        self.tracks = tracks
        let start = startingAt.flatMap { track in tracks.firstIndex { $0.id == track.id } } ?? 0
        currentIndex = tracks.indices.dropFirst(start).first { !tracks[$0].fileMissing }
    }

    @discardableResult
    public mutating func next() -> TrackRow? {
        guard let currentIndex,
              let index = tracks.indices.dropFirst(currentIndex + 1).first(where: { !tracks[$0].fileMissing })
        else { return nil }
        self.currentIndex = index
        return tracks[index]
    }

    @discardableResult
    public mutating func previous() -> TrackRow? {
        guard let currentIndex,
              let index = tracks.indices.prefix(currentIndex).last(where: { !tracks[$0].fileMissing })
        else { return nil }
        self.currentIndex = index
        return tracks[index]
    }

    /// An unknown identifier or a missing file leaves the queue unchanged.
    @discardableResult
    public mutating func jump(to id: TrackRow.ID) -> TrackRow? {
        guard let index = tracks.firstIndex(where: { $0.id == id && !$0.fileMissing }) else { return nil }
        currentIndex = index
        return tracks[index]
    }
}
