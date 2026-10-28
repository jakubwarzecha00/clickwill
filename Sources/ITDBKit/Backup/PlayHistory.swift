import Foundation

extension ITLibrary {
    /// Carries play history from the current library over to the one that is about
    /// to replace it - when restoring a backup.
    ///
    /// A backup restores the library and the edits, but has no right to undo listening.
    /// Without this, restoring a week-old backup would erase a week of plays,
    /// and that is the only part of the database the user cannot recreate.
    ///
    /// Tracks are matched by `persistentID`, not `uniqueID`: the latter is an
    /// index within a single database, while the former follows the track across
    /// writes. We take the higher play count and the later date -
    /// never decreasing. A track missing from the current library
    /// keeps what it had in the backup.
    public func carryingPlayHistory(from current: ITLibrary) -> ITLibrary {
        let history = Dictionary(current.tracks.map { ($0.persistentID, $0) },
                                 uniquingKeysWith: { first, _ in first })
        return mappingTracks { track in
            guard let now = history[track.persistentID] else { return track }
            var copy = track
            copy.playCount = Swift.max(track.playCount, now.playCount)
            if let played = now.lastPlayed, played > (track.lastPlayed ?? .distantPast) {
                copy.lastPlayed = played
            }
            return copy
        }
    }
}
