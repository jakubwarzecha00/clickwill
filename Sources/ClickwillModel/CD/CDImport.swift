import Foundation
import ITDBKit

/// An album from a disc before ripping: what the user sees and corrects.
public struct CDDraft: Sendable, Equatable {

    public struct Song: Sendable, Equatable, Identifiable {
        public let number: Int
        public var title: String
        public var artist: String
        /// An unchecked track is not ripped (e.g. a hidden track, silence).
        public var included = true
        public let durationMilliseconds: UInt32
        public let file: URL?
        public var id: Int { number }
    }

    public var album: String
    public var albumArtist: String
    public var year: String
    public var genre: String
    public var isCompilation: Bool
    public var discNumber: Int
    public var totalDiscs: Int
    public var songs: [Song]
    public var cover: Data?
    /// The MusicBrainz release the names came from.
    public var releaseID: String?

    /// A draft from the disc alone: names from the files, if macOS knows them (CD-TEXT),
    /// otherwise "Track 1", "Track 2"...
    public init(disc: AudioCD) {
        album = disc.hasTitle ? disc.volumeName : ""
        albumArtist = ""
        year = ""
        genre = ""
        isCompilation = false
        discNumber = 1
        totalDiscs = 1
        songs = disc.tracks.map { track in
            Song(number: track.number, title: disc.fileTitle(of: track) ?? "Track \(track.number)",
                 artist: "", durationMilliseconds: track.durationMilliseconds, file: track.file)
        }
    }

    /// Names from the release. Tracks are matched by number; extras from the database are skipped.
    public mutating func apply(_ release: CDRelease) {
        album = release.title
        albumArtist = release.artist
        year = release.year > 0 ? String(release.year) : ""
        if let genre = release.genre { self.genre = genre }
        isCompilation = release.isCompilation
        discNumber = release.discNumber
        totalDiscs = release.totalDiscs
        releaseID = release.id
        cover = nil
        for index in songs.indices {
            guard let track = release.tracks.first(where: { $0.number == songs[index].number })
                    ?? (release.tracks.indices.contains(index) ? release.tracks[index] : nil) else { continue }
            songs[index].title = track.title
            // The track artist only when it differs from the album - otherwise
            // the field stays empty and comes from the album.
            songs[index].artist = track.artist == release.artist ? "" : track.artist
        }
    }

    /// A pasted track list (from Wikipedia, Discogs, the booklet...). Titles
    /// go to the tracks in order. Returns the number of recognized lines; when
    /// it does not match the number of tracks, nothing changes.
    @discardableResult
    public mutating func applyPasted(_ text: String) -> Int {
        let titles = Self.titles(fromPasted: text)
        guard titles.count == songs.count else { return titles.count }
        for index in songs.indices { songs[index].title = titles[index] }
        return titles.count
    }

    /// List lines without numbering ("1.", "01 -", "A1"), without a length at the end
    /// ("5:53", "(5:53)") and without quotes. Empty lines and side headers
    /// ("Side A") drop out.
    public static func titles(fromPasted text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var title = line.trimmingCharacters(in: .whitespaces)
            title = title.replacing(/^(?:[A-Da-d]?\d{1,2})\s*[\.\)\-:–—]?\s+/, with: "")
            title = title.replacing(/\s*[\(\[]?\d{1,2}:\d{2}(?::\d{2})?[\)\]]?\s*$/, with: "")
            // Wikipedia: "Perry Mason" – 5:53 - after removing the time a dash remains.
            title = title.replacing(/\s*[-–—]\s*$/, with: "")
            title = title.replacing(/^\s*[-–—•·*]\s*/, with: "")
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”„«»' \t"))
            guard !title.isEmpty, title.wholeMatch(of: /(?i)(side|disc|cd)\s*[a-d0-9]+:?/) == nil else { return nil }
            return title
        }
    }

    public var includedSongs: [Song] { songs.filter(\.included) }

    /// What is missing before ripping - one sentence each, to show as is.
    public var missing: String? {
        if includedSongs.isEmpty { return "Choose at least one song." }
        if album.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the album a title." }
        if includedSongs.contains(where: { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }) {
            return "Every song needs a title."
        }
        return nil
    }

    func tags(for song: Song) -> FileTags {
        var tags = FileTags(title: song.title.trimmingCharacters(in: .whitespaces))
        let albumArtist = albumArtist.trimmingCharacters(in: .whitespaces)
        let artist = song.artist.trimmingCharacters(in: .whitespaces)
        tags.artist = artist.isEmpty ? (albumArtist.isEmpty ? nil : albumArtist) : artist
        tags.album = album.trimmingCharacters(in: .whitespaces)
        tags.albumArtist = albumArtist.isEmpty ? nil : albumArtist
        tags.genre = genre.trimmingCharacters(in: .whitespaces)
        tags.year = UInt32(year.trimmingCharacters(in: .whitespaces)) ?? 0
        tags.trackNumber = UInt32(song.number)
        tags.totalTracks = UInt32(songs.count)
        tags.discNumber = totalDiscs > 1 ? UInt32(discNumber) : 0
        tags.totalDiscs = totalDiscs > 1 ? UInt32(totalDiscs) : 0
        tags.isCompilation = isCompilation
        tags.cover = cover
        return tags
    }
}

/// Ripping a disc to files on the Mac.
///
/// Tracks are read one after another: two parallel reads make
/// the head jump and drop the speed to 0.4 MB/s (measured). The files
/// go to the Mac, not straight to the iPod - the disc can be ejected and the
/// drive unplugged before anything goes to the iPod through the same hub.
public enum CDRipper {

    public enum Format: String, CaseIterable, Sendable, Identifiable {
        case appleLossless, aac256, aac128

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .appleLossless: return "Apple Lossless"
            case .aac256: return "AAC 256 kbps"
            case .aac128: return "AAC 128 kbps"
            }
        }

        public var detail: String {
            switch self {
            case .appleLossless: return "Sounds exactly like the CD, at about half the size."
            case .aac256: return "Sounds like the CD to almost everyone. A fraction of the size."
            case .aac128: return "Smallest files. Good for a full iPod nano."
            }
        }

        var target: AudioCompatibility.Target {
            switch self {
            case .appleLossless: return .appleLossless(sampleRate: 44_100)
            case .aac256: return .aac(bitRate: 256_000)
            case .aac128: return .aac(bitRate: 128_000)
            }
        }

        /// Approximate size. PCM from a disc is 176,400 B/s; ALAC usually compresses
        /// music to 50-60%.
        public func estimatedBytes(milliseconds: UInt64) -> Int64 {
            let seconds = Double(milliseconds) / 1000
            switch self {
            case .appleLossless: return Int64(seconds * 176_400 * 0.55)
            case .aac256: return Int64(seconds * 32_000)
            case .aac128: return Int64(seconds * 16_000)
            }
        }
    }

    /// `~/Music/Clickwill` - ripped discs stay on the Mac as an archive.
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("Clickwill")
    }

    /// `<root>/<album artist>/<album>`.
    public static func folder(for draft: CDDraft, root: URL = defaultRoot) -> URL {
        let artist = draft.isCompilation ? "Compilations" : draft.albumArtist
        return root.appendingPathComponent(safeName(artist, fallback: "Unknown Artist"), isDirectory: true)
            .appendingPathComponent(safeName(draft.album, fallback: "Unknown Album"), isDirectory: true)
    }

    /// "01 Perry Mason.m4a", with the disc number before the track number when there are several discs.
    static func fileName(for song: CDDraft.Song, in draft: CDDraft) -> String {
        let number = String(format: "%02d", song.number)
        let prefix = draft.totalDiscs > 1 ? "\(draft.discNumber)-\(number)" : number
        return "\(prefix) \(safeName(song.title, fallback: "Track \(song.number)")).m4a"
    }

    static func safeName(_ text: String, fallback: String) -> String {
        let cleaned = text.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(120))
    }

    public struct Outcome: Sendable {
        public var files: [URL] = []
        public var failed: [Failure] = []
        public var folder: URL
    }

    /// A track or folder that was not ripped, and why. The app builds the sentence.
    public struct Failure: Sendable, CustomStringConvertible {
        public enum Reason: Sendable {
            /// The folder for ripped files could not be created (`subject` - its path).
            case folderNotCreated(any Error)
            /// The disc has no file for this track.
            case trackMissing
            /// Reading or converting failed.
            case error(any Error)
        }

        /// The song title or the folder path.
        public let subject: String
        public let reason: Reason

        public var description: String {
            switch reason {
            case .folderNotCreated(let error): "\(subject): mkdir failed: \(error)"
            case .trackMissing: "\(subject): track file missing"
            case .error(let error): "\(subject): \(error)"
            }
        }
    }

    /// Rips the checked tracks. `progress(index, fraction)` - the index among
    /// the checked ones. A track that cannot be read (a scratch) goes to
    /// `failed`, the rest goes on.
    /// `pace`: a pause after each track - only in demo recordings, where
    /// one-second files would rip faster than anyone could see.
    public static func rip(_ draft: CDDraft, as format: Format, root: URL = defaultRoot, pace: Duration? = nil,
                           progress: (@Sendable (Int, Double) -> Void)? = nil) async -> Outcome {
        let folder = folder(for: draft, root: root)
        var outcome = Outcome(folder: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            outcome.failed.append(Failure(subject: folder.path, reason: .folderNotCreated(error)))
            return outcome
        }
        for (index, song) in draft.includedSongs.enumerated() {
            if Task.isCancelled { break }
            guard let source = song.file else {
                outcome.failed.append(Failure(subject: song.title, reason: .trackMissing))
                continue
            }
            do {
                let converted = try await AudioFiles.convert(source, to: format.target, tags: draft.tags(for: song)) {
                    progress?(index, $0)
                }
                let destination = folder.appendingPathComponent(fileName(for: song, in: draft))
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: converted)
                } else {
                    try FileManager.default.moveItem(at: converted, to: destination)
                }
                outcome.files.append(destination)
                progress?(index, 1)
                if let pace { try? await Task.sleep(for: pace) }
            } catch {
                outcome.failed.append(Failure(subject: song.title, reason: .error(error)))
            }
        }
        return outcome
    }
}
