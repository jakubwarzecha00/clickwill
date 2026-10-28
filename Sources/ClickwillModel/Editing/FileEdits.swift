import Foundation
import ITDBKit

/// Files: restoring a missing one, replacing, converting to a format the
/// iPod plays, and new tracks. The library stays unchanged - everything waits
/// in the change queue and happens only during the write.
extension LibraryEditor {

    // MARK: - The file of an existing track

    /// Puts a file into the queue for an entry without a file. A track that has a file
    /// is rejected - that is what `replaceFile` is for, and `convertTrack` changes the format.
    mutating func importFile(_ candidate: ImportCandidate, for row: TrackRow, in album: AlbumCard) throws {
        guard row.fileMissing else { throw FileImportError.notMissing(row.displayTitle) }
        if case .rejected(let reason) = candidate.verdict {
            throw FileImportError.rejected(candidate.url, reason: reason)
        }
        changes.queueFileImport(Self.fileImport(candidate, for: row, album: title(of: album)))
    }

    /// Queues replacing the file of a track that already has one.
    ///
    /// A separate command, not a lifted check in `importFile`: that one refuses
    /// when there is a file, and that is the safeguard against accidental overwriting.
    /// A replacement must be an intent, not a side effect.
    ///
    /// The track record stays the same - title, number, plays, rating,
    /// place in playlists and artwork. Only the file changes, and what
    /// follows from the file: size, length, bitrate, sample rate and kind.
    mutating func replaceFile(_ candidate: ImportCandidate, for row: TrackRow, in album: AlbumCard) throws {
        guard !row.fileMissing else { return try importFile(candidate, for: row, in: album) }
        if case .rejected(let reason) = candidate.verdict {
            throw FileImportError.rejected(candidate.url, reason: reason)
        }
        // Without the current file's URL we do not know what to delete after the write - and
        // a replacement that leaves the old file in an unknown place creates a ghost.
        guard let existing = fileURL(of: row.id) else { throw FileImportError.currentFileUnknown(row.displayTitle) }
        // The same file chosen a second time is not a replacement - the write would delete
        // it as "old" after copying it as "new".
        guard existing.standardizedFileURL != candidate.url.standardizedFileURL else {
            throw FileImportError.sameFile(row.displayTitle)
        }
        var job = Self.fileImport(candidate, for: row, album: title(of: album))
        job.replacing = existing
        changes.queueFileImport(job)
    }

    mutating func cancelFileImport(_ trackID: UInt32) {
        changes.cancelFileImport(trackID)
    }

    /// Queues converting a track to a format the iPod plays.
    /// `archiveDirectory` is the folder for the original; `nil` requires the caller
    /// to deliberately give up the copy - a 24 -> 16 bit conversion loses information.
    mutating func convertTrack(_ row: TrackRow, in album: AlbumCard, keepOriginalsIn archiveDirectory: URL?) throws {
        let albumTitle = title(of: album)
        guard let track = record(row.id), let url = track.fileURL(on: paths),
              files.fileExists(at: url) else {
            throw ConversionQueueError.fileMissing(row.displayTitle)
        }
        guard let verdict = formatVerdicts[row.id] else { throw ConversionQueueError.notScanned(row.displayTitle) }
        guard case .convertible(_, let target) = verdict else {
            throw ConversionQueueError.notConvertible(row.displayTitle, reason: verdict.reason ?? "already playable")
        }
        changes.queueConversion(trackID: row.id, album: albumTitle, title: row.displayTitle, source: url, to: target,
                                fromLabel: formatLabels[row.id] ?? "", keepOriginalIn: archiveDirectory)
    }

    /// The request for an entry. The kind after conversion, not before - otherwise the record
    /// would describe a FLAC that is no longer on the device.
    private static func fileImport(_ candidate: ImportCandidate, for row: TrackRow, album: String) -> PendingFileImport {
        PendingFileImport(
            id: row.id, album: album, title: row.displayTitle, source: candidate.url,
            verdict: candidate.verdict, formatLabel: candidate.formatLabel,
            durationMilliseconds: candidate.durationMilliseconds,
            bitRate: candidate.bitRate, sampleRate: candidate.sampleRate,
            kind: candidate.target?.kindForDevice ?? candidate.kind)
    }

    // MARK: - New tracks

    /// Adds files to the add queue. Returns what cannot be added.
    mutating func queueAdditions(_ candidates: [AudioImport.Candidate]) -> [QueueRefusal] {
        var refused: [QueueRefusal] = []
        for candidate in candidates {
            if let reason = changes.queueAddition(PendingAddition(candidate)) { refused.append(QueueRefusal(candidate.draft.title, reason)) }
        }
        return refused
    }

    /// Adds files straight to an album: from the album menu or dropped onto the track
    /// list. The album fields come from a track already in it, so the new
    /// track lands in this album regardless of its tags. `index` is the place
    /// in the list (nil = at the end); several files stand in turn from that place.
    /// `read`: the files with what was read from them (`nil` - not audio).
    /// Returns what cannot be added.
    mutating func addFiles(_ read: [(url: URL, candidate: AudioImport.Candidate?)], to album: AlbumCard, at index: Int?) -> [QueueRefusal] {
        guard let album = current(album), let sibling = records(of: album).first else {
            return [QueueRefusal(album.title, .noSongsToMatch)]
        }
        let count = album.trackIndices.count
        var position = min(max(index ?? count, 0), count)
        var refused: [QueueRefusal] = []
        for (url, read) in read {
            guard var candidate = read else {
                refused.append(QueueRefusal(url.lastPathComponent, .notAudio))
                continue
            }
            candidate.draft.album = sibling.album
            candidate.draft.albumArtist = sibling.albumArtist
            candidate.draft.isCompilation = sibling.isCompilation
            if (candidate.draft.artist ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                candidate.draft.artist = sibling.artist ?? sibling.albumArtist
            }
            candidate.draft.trackNumber = UInt32(position + 1)
            var addition = PendingAddition(candidate)
            addition.placement = AlbumPlacement(album: sibling.album ?? album.title, albumKey: sibling.albumKey, index: position)
            if let reason = changes.queueAddition(addition) {
                refused.append(QueueRefusal(candidate.draft.title, reason))
                continue
            }
            position += 1
        }
        return refused
    }

    /// Withdraws tracks from the add queue before they reach the iPod.
    mutating func removeQueuedAdditions(_ ids: Set<UUID>) {
        changes.removeAdditions(ids)
    }
}
