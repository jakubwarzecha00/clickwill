import Foundation
import ITDBKit

/// An album from the iPod that matches a group of files in an import - even when the files
/// have no tags or have them written differently (e.g. AIFF from a CD, where the album
/// is the folder name and there is no artist at all). Without this such an import
/// created a second, duplicated album.
public struct AlbumMatch: Sendable {
    public let album: AlbumCard
    /// A file from the import -> the track on the iPod that this file will replace.
    public let pairs: [UUID: TrackRow]
    /// Files without a counterpart on the iPod (e.g. a bonus track).
    public let extraCandidates: [UUID]
    /// Tracks of the album for which the import has no file.
    public let missingRows: [TrackRow]

    public var isComplete: Bool { extraCandidates.isEmpty && missingRows.isEmpty }
}

extension LibraryModel {

    /// The best matching album on the iPod, or `nil`. A pair is the same title
    /// (ignoring case, punctuation and accents; a note in brackets like
    /// "[Live]" may or may not be there) and the length within 2 s. When the titles
    /// diverge (a file without tags), the second key is the track number and the length
    /// within 1 s. An album matches when at least two tracks agree
    /// and at least 60% of the group's files.
    public func matchingAlbum(for songs: [AudioImport.Candidate]) -> AlbumMatch? {
        guard songs.count > 0 else { return nil }
        var best: AlbumMatch?
        for album in albums {
            let rows = tracks(of: album)
            guard !rows.isEmpty else { continue }
            let match = Self.pair(songs, with: rows, album: album)
            let needed = max(2, Int((Double(songs.count) * 0.6).rounded(.up)))
            guard match.pairs.count >= min(needed, songs.count), match.pairs.count >= min(2, songs.count) else { continue }
            if match.pairs.count > (best?.pairs.count ?? 0) { best = match }
        }
        return best
    }

    nonisolated static func pair(_ songs: [AudioImport.Candidate], with rows: [TrackRow], album: AlbumCard) -> AlbumMatch {
        var free = rows
        var pairs: [UUID: TrackRow] = [:]
        // Title and length first, then number and length - so that the surer
        // pairs do not give a track away to weaker ones.
        for song in songs {
            let names = titleKeys(song.draft.title)
            if let index = free.firstIndex(where: { row in
                !names.isDisjoint(with: titleKeys(row.title)) && close(row.duration, song.draft.durationMilliseconds, 2_000)
            }) {
                pairs[song.id] = free.remove(at: index)
            }
        }
        for song in songs where pairs[song.id] == nil && song.draft.trackNumber > 0 {
            if let index = free.firstIndex(where: { row in
                row.number == song.draft.trackNumber && close(row.duration, song.draft.durationMilliseconds, 1_000)
            }) {
                pairs[song.id] = free.remove(at: index)
            }
        }
        return AlbumMatch(album: album, pairs: pairs,
                          extraCandidates: songs.map(\.id).filter { pairs[$0] == nil },
                          missingRows: free)
    }

    /// The title in a form for comparison, with a version without notes in brackets.
    nonisolated static func titleKeys(_ title: String) -> Set<String> {
        func squash(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init).joined()
        }
        let full = squash(title)
        let base = squash(title.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression))
        return Set([full, base].filter { !$0.isEmpty })
    }

    nonisolated static func close(_ seconds: TimeInterval, _ milliseconds: UInt32, _ tolerance: UInt32) -> Bool {
        abs(Int(seconds * 1000) - Int(milliseconds)) <= Int(tolerance)
    }

    /// Replacing files in an existing album: each file from a pair goes into
    /// the queue as a new file of the same track (the title, plays, rating,
    /// artwork and place stay). Returns what could not be replaced.
    @discardableResult
    public func replaceFiles(_ candidates: [AudioImport.Candidate], using match: AlbumMatch) -> [QueueRefusal] {
        var refused: [QueueRefusal] = []
        for candidate in candidates {
            guard let row = match.pairs[candidate.id] else { continue }
            let draft = candidate.draft
            let file = ImportCandidate(
                url: candidate.url, verdict: candidate.verdict, formatLabel: candidate.formatLabel,
                durationMilliseconds: draft.durationMilliseconds, taggedTitle: draft.title,
                trackNumber: draft.trackNumber, sizeBytes: draft.sizeBytes, bitRate: draft.bitRate,
                sampleRate: draft.sampleRate, kind: draft.kind)
            do { try replaceFile(file, for: row, in: match.album) }
            catch { refused.append(QueueRefusal(row.displayTitle, .error(error))) }
        }
        return refused
    }

    /// Album fields for attaching an extra file to an existing album.
    public func albumFields(of album: AlbumCard) -> AlbumFields? {
        guard let library else { return nil }
        let all = library.tracks
        guard let sibling = album.trackIndices.first.flatMap({ $0 < all.count ? all[$0] : nil }) else { return nil }
        return AlbumFields(album: sibling.album, albumArtist: sibling.albumArtist, artist: sibling.artist,
                           isCompilation: sibling.isCompilation)
    }
}
