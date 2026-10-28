import ITDBKit

/// The order of checking files during the format scan.
///
/// Tracks go in library order, but the album open on screen jumps
/// to the front: on a Classic a scan of over a thousand files takes about two minutes,
/// and an album from the end of the list would look fine until then. Each track
/// leaves the queue exactly once.
struct FormatScanQueue {
    private let tracks: [ITTrack]
    /// The next track in library order.
    private var position = 0
    /// Positions of the open album's tracks that have not left yet.
    private var prioritized: [Int] = []
    private var taken: Set<Int> = []

    init(_ tracks: [ITTrack]) {
        self.tracks = tracks
    }

    /// These tracks go next. A later call replaces the previous one:
    /// what counts is the album on screen now.
    mutating func prioritize(_ trackIDs: some Sequence<UInt32>) {
        let wanted = Set(trackIDs)
        prioritized = tracks.indices.filter { wanted.contains(tracks[$0].uniqueID) && !taken.contains($0) }
    }

    mutating func next() -> ITTrack? {
        while !prioritized.isEmpty {
            let index = prioritized.removeFirst()
            if taken.insert(index).inserted { return tracks[index] }
        }
        while position < tracks.count {
            defer { position += 1 }
            if taken.insert(position).inserted { return tracks[position] }
        }
        return nil
    }
}
