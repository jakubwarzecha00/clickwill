import Foundation
import AVFoundation
import ITDBKit

/// Reading an audio file in order to add it to the library.
///
/// Tags are taken from three sources at once, because none is enough: the common
/// AVFoundation keys give the title and album, but not the track number; iTunes keeps
/// the number in a binary field; MP3 in text of the form "3/12". What is missing stays
/// empty - we do not guess.
public enum AudioImport {

    /// What we know about the file before it reaches the device.
    public struct Candidate: Sendable, Identifiable {
        public let id = UUID()
        public let url: URL
        public var draft: TrackDraft
        /// The format compatibility verdict. A file the iPod will not play does not go
        /// into the database in this form - it goes through conversion or drops out.
        public let verdict: AudioCompatibility.Verdict
        public let formatLabel: String
        /// Artwork embedded in the file, if any.
        public let artwork: Data?
        /// An artwork file lying next to it in the folder (cover.jpg, folder.jpg...).
        /// Used when the tags have nothing - that is how most ripped albums
        /// keep their artwork.
        public var folderCover: URL?
        /// Artwork chosen by hand in the interface. It takes precedence over
        /// everything else: it is the only source that comes directly from
        /// the user, and the other two are guesses - good ones, but guesses.
        public var chosenCover: URL?

        /// Where to get artwork for this album, if at all.
        public var coverSource: CoverSource? {
            if let chosenCover { return .file(chosenCover) }
            if let artwork { return .embedded(artwork) }
            if let folderCover { return .file(folderCover) }
            return nil
        }

        /// Where the artwork comes from - to say so plainly in the interface.
        public enum CoverOrigin: Sendable { case chosen, tags, folder, none }
        public var coverOrigin: CoverOrigin {
            if chosenCover != nil { return .chosen }
            if artwork != nil { return .tags }
            if folderCover != nil { return .folder }
            return .none
        }

        /// A file the iPod will not play and that we cannot transcode.
        public var isHopeless: Bool {
            if case .rejected = verdict { return true }
            return false
        }
    }

    public enum CoverSource: Sendable, Equatable {
        case embedded(Data)
        case file(URL)

        public var label: String {
            switch self {
            case .embedded: return "from the file's tags"
            case .file(let url): return "from \(url.lastPathComponent)"
            }
        }
    }

    public enum ImportError: Error, CustomStringConvertible {
        case unreadable(URL)
        case unsupportedFormat(URL, reason: String)

        public var description: String {
            switch self {
            case .unreadable(let url): "unreadable audio file \(url.lastPathComponent)"
            case .unsupportedFormat(let url, let reason): "\(url.lastPathComponent) unsupported: \(reason)"
            }
        }
    }

    /// Reads a file and assembles a candidate. `relativePath` is still empty - the file
    /// gets its place on the device only during the write.
    public static func candidate(at url: URL, on device: IPodCapabilities = .classic) async throws -> Candidate {
        guard let stream = await AudioFiles.stream(at: url) else { throw ImportError.unreadable(url) }
        let verdict = AudioCompatibility.verdict(for: stream, on: device)
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []
        let common = (try? await asset.load(.commonMetadata)) ?? []
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        let all = metadata + common
        let title = await string(all, .commonIdentifierTitle, .iTunesMetadataSongName, .id3MetadataTitleDescription)
        var (number, total) = await pair(all, .iTunesMetadataTrackNumber, .id3MetadataTrackNumber)
        var (disc, discs) = await pair(all, .iTunesMetadataDiscNumber, .id3MetadataPartOfASet)
        if number == 0 { (number, total) = await vorbisPair(all, "TRACKNUMBER", totals: "TRACKTOTAL", "TOTALTRACKS") }
        if disc == 0 { (disc, discs) = await vorbisPair(all, "DISCNUMBER", totals: "DISCTOTAL", "TOTALDISCS") }
        // FLAC and Ogg have these fields only as Vorbis tags (see `vorbisItems`).
        var albumArtist = await string(all, .iTunesMetadataAlbumArtist, .id3MetadataBand)
        if albumArtist == nil { albumArtist = await vorbisString(all, "ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST") }
        var genre = await string(all, .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre, .id3MetadataContentType)
        if genre == nil { genre = await vorbisString(all, "GENRE") }
        var composer = await string(all, .iTunesMetadataComposer, .id3MetadataComposer)
        if composer == nil { composer = await vorbisString(all, "COMPOSER") }
        var comment = await string(all, .iTunesMetadataUserComment, .id3MetadataComments)
        if comment == nil { comment = await vorbisString(all, "COMMENT", "DESCRIPTION") }
        var isCompilation = await flag(all, .iTunesMetadataDiscCompilation)
        if !isCompilation { isCompilation = await vorbisString(all, "COMPILATION") == "1" }

        // The kind is needed for choosing the `mhit` template; for a file the iPod
        // will not play, the conversion target format decides anyway.
        let kind = TrackFileKind.from(formatID: stream.formatID, fileExtension: url.pathExtension) ?? .appleLossless

        // A file without a title tag: we take the name, but without the leading number -
        // "01 - Song.mp3" is the title "Song" and track number 1, not a title
        // starting with digits.
        let fromName = fileNameTitle(url)
        let draft = TrackDraft(
            title: title ?? fromName.title,
            artist: await string(all, .commonIdentifierArtist, .iTunesMetadataArtist, .id3MetadataLeadPerformer),
            albumArtist: albumArtist,
            album: await string(all, .commonIdentifierAlbumName, .iTunesMetadataAlbum, .id3MetadataAlbumTitle),
            genre: genre,
            composer: composer,
            comment: comment,
            year: await year(all),
            trackNumber: number > 0 ? number : (title == nil ? fromName.number : 0), totalTracks: total,
            discNumber: disc, totalDiscs: discs,
            isCompilation: isCompilation,
            durationMilliseconds: UInt32(clamping: Int(duration.isFinite ? duration * 1000 : 0)),
            sizeBytes: UInt32(clamping: size),
            bitRate: UInt32(clamping: stream.bitRate / 1000),
            sampleRate: UInt32(clamping: stream.sampleRate),
            kind: kind, relativePath: "")

        return Candidate(url: url, draft: draft, verdict: verdict,
                         formatLabel: AudioCompatibility.label(for: stream),
                         artwork: await artwork(all))
    }

    /// Reads a folder or a list of files; folders are walked recursively.
    /// The order is by file name - the only sensible order before
    /// we know the track numbers.
    /// Folders are expanded to audio files (with subfolders, by extension,
    /// without hidden files, in path order); single files stay
    /// as they are, in the given order - whether they are audio is decided
    /// by reading the file, and a refusal goes to the user.
    public static func expandingFolders(_ urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else { found.append(url); continue }
            var inside: [URL] = []
            let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            while let item = contents?.nextObject() as? URL {
                guard !item.hasDirectoryPath, audioExtensions.contains(item.pathExtension.lowercased()) else { continue }
                inside.append(item)
            }
            found += inside.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        return found
    }

    public static func candidates(at urls: [URL], on device: IPodCapabilities = .classic) async -> (ready: [Candidate], problems: [any Error]) {
        let found = expandingFolders(urls).filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        var ready: [Candidate] = []
        var problems: [any Error] = []
        var coverCache: [String: URL?] = [:]
        for url in found.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            do {
                var candidate = try await candidate(at: url, on: device)
                let directory = url.deletingLastPathComponent()
                // An album without a tag takes the folder name - that is how most
                // ripped discs look, and that is what the person who ripped them called them.
                if (candidate.draft.album ?? "").isEmpty, directory.lastPathComponent != "/" {
                    candidate.draft.album = directory.lastPathComponent
                }
                if candidate.artwork == nil {
                    if let cached = coverCache[directory.path] {
                        candidate.folderCover = cached
                    } else {
                        let found = coverFile(in: directory)
                        coverCache[directory.path] = found
                        candidate.folderCover = found
                    }
                }
                ready.append(candidate)
            } catch { problems.append(error) }
        }
        return (numbered(ready), problems)
    }

    /// The title and number from the file name. We recognize the layouts actually
    /// found in ripped albums: "01 Title", "01 - Title", "01. Title",
    /// "01_Title". The number is taken only when something remains after it - a file
    /// named with just a number keeps it as the title.
    static func fileNameTitle(_ url: URL) -> (title: String, number: UInt32) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let match = name.firstMatch(of: /^\s*(\d{1,3})\s*[-._)]?\s+(.+)$/) ?? name.firstMatch(of: /^\s*(\d{1,3})[-._)]\s*(.+)$/),
              let number = UInt32(match.1) else {
            return (name, 0)
        }
        let rest = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return (name, 0) }
        return (rest, number)
    }

    /// Numbers the tracks of an album that has no numbers. Without numbers the iPod would lay out
    /// the record alphabetically by title, which usually makes no sense for an album;
    /// the order of files in the folder is the only information we have, and it is usually
    /// right. An album in which even one track has a number is left alone -
    /// someone has already made a decision there.
    static func numbered(_ candidates: [Candidate]) -> [Candidate] {
        var result = candidates
        let groups = Dictionary(grouping: candidates.indices) { candidates[$0].draft.albumKey }
        for (_, indices) in groups {
            guard indices.count > 1,
                  indices.allSatisfy({ candidates[$0].draft.trackNumber == 0 }) else { continue }
            for (position, index) in indices.sorted().enumerated() {
                result[index].draft.trackNumber = UInt32(position + 1)
                result[index].draft.totalTracks = UInt32(indices.count)
            }
        }
        return result
    }

    /// Artwork lying in the album's folder. Names in the order in which they are
    /// found in ripped albums.
    static func coverFile(in directory: URL) -> URL? {
        let names = ["cover", "folder", "front", "album", "albumart", "artwork"]
        let extensions = ["jpg", "jpeg", "png", "webp", "heic"]
        let manager = FileManager.default
        guard let contents = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        let images = contents.filter { extensions.contains($0.pathExtension.lowercased()) }
        for name in names {
            if let match = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }) {
                return match
            }
        }
        // The only image in the folder is almost certainly the artwork, whatever its name.
        return images.count == 1 ? images.first : nil
    }

    /// Extensions we consider at all. Those the iPod does not play
    /// too - so we can say so plainly instead of silently skipping them.
    public static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "ogg", "oga", "opus", "wma", "ape", "alac",
    ]

    // MARK: - Extracting fields

    static func string(_ items: [AVMetadataItem], _ identifiers: AVMetadataIdentifier...) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// A number and a total - "3/12" in text or the iTunes binary field,
    /// in which the number lies at bytes 2-3, and the total at 4-5.
    static func pair(_ items: [AVMetadataItem], _ identifiers: AVMetadataIdentifier...) async -> (UInt32, UInt32) {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let data = try? await item.load(.dataValue), data.count >= 6 {
                    let bytes = [UInt8](data)
                    return (UInt32(bytes[2]) << 8 | UInt32(bytes[3]), UInt32(bytes[4]) << 8 | UInt32(bytes[5]))
                }
                if let text = try? await item.load(.stringValue) {
                    let parts = text.split(separator: "/")
                    let number = UInt32(parts.first.map(String.init) ?? "") ?? 0
                    let total = parts.count > 1 ? UInt32(String(parts[1])) ?? 0 : 0
                    if number > 0 { return (number, total) }
                }
                if let number = try? await item.load(.numberValue) {
                    return (UInt32(clamping: number.intValue), 0)
                }
            }
        }
        return (0, 0)
    }

    /// Vorbis tags from FLAC and Ogg files. AVFoundation gives them as
    /// `vorb/<KEY>` with the case as in the file and without iTunes
    /// or ID3 equivalents, and the field names depend on the program that did the tagging
    /// ("ALBUMARTIST" or "ALBUM ARTIST"). Common fields (title, artist,
    /// album, date, artwork) go through `commonKey` and are not needed here.
    /// Without this a FLAC album fell apart into as many albums as there were
    /// artists in its tracks.
    static func vorbisItems(_ items: [AVMetadataItem], _ keys: [String]) -> [AVMetadataItem] {
        // A space in the key arrives as %20 ("vorb/ALBUM%20ARTIST").
        func normalized(_ raw: String) -> String { (raw.removingPercentEncoding ?? raw).uppercased() }
        return keys.flatMap { key in
            items.filter { $0.identifier.map { normalized($0.rawValue) } == normalized("vorb/" + key) }
        }
    }

    static func vorbisString(_ items: [AVMetadataItem], _ keys: String...) async -> String? {
        await vorbisString(items, keys)
    }

    static func vorbisString(_ items: [AVMetadataItem], _ keys: [String]) async -> String? {
        for item in vorbisItems(items, keys) {
            if let value = try? await item.load(.stringValue)?.trimmingCharacters(in: .whitespaces), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// The number as "3" or "3/12"; the total can also be in a separate
    /// field (TRACKTOTAL, TOTALTRACKS).
    static func vorbisPair(_ items: [AVMetadataItem], _ key: String, totals: String...) async -> (UInt32, UInt32) {
        guard let text = await vorbisString(items, key) else { return (0, 0) }
        let parts = text.split(separator: "/")
        let number = UInt32(parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "") ?? 0
        var total = parts.count > 1 ? UInt32(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        if total == 0, let text = await vorbisString(items, totals) { total = UInt32(text) ?? 0 }
        return (number, total)
    }

    static func year(_ items: [AVMetadataItem]) async -> UInt32 {
        for identifier in [AVMetadataIdentifier.commonIdentifierCreationDate, .iTunesMetadataReleaseDate,
                           .id3MetadataYear, .id3MetadataRecordingTime] {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let text = try? await item.load(.stringValue),
                   let match = text.firstMatch(of: /(\d{4})/), let value = UInt32(match.1) {
                    return value
                }
                if let number = try? await item.load(.numberValue), number.intValue > 1000 {
                    return UInt32(clamping: number.intValue)
                }
            }
        }
        return 0
    }

    static func flag(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> Bool {
        for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
            if let number = try? await item.load(.numberValue) { return number.intValue != 0 }
        }
        return false
    }

    static func artwork(_ items: [AVMetadataItem]) async -> Data? {
        for identifier in [AVMetadataIdentifier.commonIdentifierArtwork, .iTunesMetadataCoverArt,
                           .id3MetadataAttachedPicture] {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let data = try? await item.load(.dataValue), !data.isEmpty { return data }
            }
        }
        return nil
    }
}
