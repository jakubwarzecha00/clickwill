import Foundation

/// The `Play Counts` file - what the iPod has counted since the last sync.
///
/// The iPod records plays and skips here, and iTunes merges them into `iTunesDB`
/// during sync and clears the file. Every rewrite of the database must do the same,
/// or listening history is lost.
///
/// Entries have no identifiers - they correspond to tracks **by position**, in the same
/// order in which the `mhit` records appear.
public struct PlayCounts: Sendable {

    public struct Entry: Sendable {
        public let playCount: UInt32
        public let lastPlayed: Date?
        public let bookmarkMilliseconds: UInt32
        public let rating: UInt32
        public let skipCount: UInt32
        public let lastSkipped: Date?
        /// The field at offset 0x10, whose meaning we have not established.
        /// In the test database it takes the values 256 and 512 for every entry.
        public let unknownField: UInt32

        public var isEmpty: Bool {
            playCount == 0 && lastPlayed == nil && bookmarkMilliseconds == 0
                && rating == 0 && skipCount == 0 && lastSkipped == nil
        }
    }

    public let entries: [Entry]
    public let entryLength: Int
    public let rawHeader: [UInt8]

    /// Whether the layout was measured on hardware (`ConfirmedModels.playCountsLayouts`). On a
    /// model outside the confirmed ones the file is merged only in such a layout - the firmware
    /// writes it after a database it loads, so refusing it outright would block writing.
    public var hasMeasuredLayout: Bool {
        ConfirmedModels.playCountsLayouts.contains(.init(header: rawHeader.count, entry: entryLength))
    }

    public var layoutSummary: String { "header \(rawHeader.count) B, entries \(entryLength) B" }

    /// Entries carrying anything new.
    public var pending: [(index: Int, entry: Entry)] {
        entries.enumerated().compactMap { $0.element.isEmpty ? nil : ($0.offset, $0.element) }
    }

    public static func parse(_ data: Data) throws -> PlayCounts {
        let reader = ByteReader(data)
        guard try reader.signature(at: 0) == "mhdp" else {
            throw ITDBError.unexpectedSignature(expected: "mhdp", found: try reader.signature(at: 0), offset: 0)
        }
        let headerLength = Int(try reader.u32(at: 4))
        let entryLength = Int(try reader.u32(at: 8))
        let count = Int(try reader.u32(at: 12))

        let expected = headerLength + entryLength * count
        guard expected == reader.count else {
            throw ITDBError.lengthMismatch(declared: expected, actual: reader.count)
        }
        guard entryLength >= 28 else {
            throw ITDBError.databaseTooSmall(bytes: entryLength, needed: 28)
        }

        var entries: [Entry] = []
        entries.reserveCapacity(count)
        for index in 0..<count {
            let offset = headerLength + index * entryLength
            entries.append(
                Entry(
                    playCount: try reader.u32(at: offset),
                    lastPlayed: MacTime.date(from: try reader.u32(at: offset + 0x04)),
                    bookmarkMilliseconds: try reader.u32(at: offset + 0x08),
                    rating: try reader.u32(at: offset + 0x0C),
                    skipCount: try reader.u32(at: offset + 0x14),
                    lastSkipped: MacTime.date(from: try reader.u32(at: offset + 0x18)),
                    unknownField: try reader.u32(at: offset + 0x10)
                )
            )
        }

        return PlayCounts(
            entries: entries,
            entryLength: entryLength,
            rawHeader: try reader.slice(0..<headerLength)
        )
    }

    /// Applies pending statistics to tracks. Returns the number of entries changed.
    ///
    /// Plays add up, dates take the newer value - the iPod and the database may
    /// both hold part of the history.
    public static func merged(
        into tracks: [ITTrack], from counts: PlayCounts
    ) -> (playCounts: [UInt32: UInt32], lastPlayed: [UInt32: Date], changed: Int) {
        var mergedCounts: [UInt32: UInt32] = [:]
        var mergedDates: [UInt32: Date] = [:]
        var changed = 0

        for (index, track) in tracks.enumerated() {
            guard index < counts.entries.count else { break }
            let entry = counts.entries[index]
            guard !entry.isEmpty else { continue }

            if entry.playCount > 0 {
                mergedCounts[track.uniqueID] = track.playCount + entry.playCount
                changed += 1
            }
            if let played = entry.lastPlayed, played > (track.lastPlayed ?? .distantPast) {
                mergedDates[track.uniqueID] = played
                if entry.playCount == 0 { changed += 1 }
            }
        }
        return (mergedCounts, mergedDates, changed)
    }

    /// Applies pending plays to the outgoing database as an increment, not as the
    /// absolute value from the database on disk. The difference matters when
    /// the caller changed the count itself: merging duplicates adds the plays of
    /// the removed copy to the one that stays, and overwriting with the value from disk
    /// would lose them.
    ///
    /// `redirects` (removed -> kept) carries the pending plays of the
    /// removed track over to the one that replaces it. Tracks removed without
    /// a redirect simply do not get them.
    public static func applying(
        _ counts: PlayCounts, recordedFor onDisk: [ITTrack], to library: ITLibrary,
        redirects: [UInt32: UInt32] = [:]
    ) -> (library: ITLibrary, changed: Int) {
        var plays: [UInt32: UInt32] = [:]
        var dates: [UInt32: Date] = [:]
        var changed = 0

        for (index, track) in onDisk.enumerated() {
            guard index < counts.entries.count else { break }
            let entry = counts.entries[index]
            guard !entry.isEmpty else { continue }
            let target = redirects[track.uniqueID] ?? track.uniqueID

            if entry.playCount > 0 {
                plays[target, default: 0] += entry.playCount
                changed += 1
            }
            if let played = entry.lastPlayed, played > (track.lastPlayed ?? .distantPast) {
                if played > (dates[target] ?? .distantPast) { dates[target] = played }
                if entry.playCount == 0 { changed += 1 }
            }
        }
        guard changed > 0 else { return (library, 0) }

        let updated = library.mappingTracks { track in
            var copy = track
            if let extra = plays[track.uniqueID] { copy.playCount += extra }
            if let date = dates[track.uniqueID], date > (copy.lastPlayed ?? .distantPast) { copy.lastPlayed = date }
            return copy
        }
        return (updated, changed)
    }
}
