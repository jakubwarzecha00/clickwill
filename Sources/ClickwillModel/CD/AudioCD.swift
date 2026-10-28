import Foundation
import CryptoKit

/// An audio CD in the drive.
///
/// Ripping needs neither Music nor any library: macOS mounts the
/// disc (cddafs) as a volume with ready AIFF files, one per track,
/// and puts a `.TOC.plist` with the table of contents next to them. From the table we compute the
/// MusicBrainz Disc ID and the track lengths to the sector. There are usually no names on the disc
/// (CD-TEXT is rare, and discs from before 1996 do not have it at all) - the files
/// are called "1 Audio Track.aiff" (measured on the Ozzmosis disc).
public struct AudioCD: Sendable, Equatable, Identifiable {

    public struct Track: Sendable, Equatable, Identifiable {
        public let number: Int
        /// The track's first sector, already with the 150 offset (as in the table).
        public let startSector: Int
        public let sectorCount: Int
        /// The track file on the mounted volume.
        public let file: URL?

        public var id: Int { number }
        /// 75 sectors per second.
        public var duration: TimeInterval { Double(sectorCount) / 75 }
        public var durationMilliseconds: UInt32 { UInt32(sectorCount * 1000 / 75) }
    }

    public let volume: URL
    /// The volume name: "Audio CD", until something gives the disc a name.
    public let volumeName: String
    /// Audio tracks. A data track (an "Enhanced CD") is not music.
    public let tracks: [Track]
    /// The first and last track and the lead-out in the form the Disc ID needs.
    let discIDFirst: Int
    let discIDLast: Int
    let discIDLeadout: Int
    let discIDOffsets: [Int]

    public var id: URL { volume }
    public var duration: TimeInterval { tracks.reduce(0) { $0 + $1.duration } }

    public enum ReadError: Error, CustomStringConvertible {
        case notAnAudioCD(URL)
        case noAudioTracks

        public var description: String {
            switch self {
            case .notAnAudioCD(let url): "\(url.lastPathComponent): no .TOC.plist"
            case .noAudioTracks: "no audio tracks on the disc"
            }
        }
    }

    /// Audio CDs mounted right now.
    public static func mounted() -> [AudioCD] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                            options: [.skipHiddenVolumes]) ?? []
        return volumes.compactMap { try? AudioCD(volume: $0) }
    }

    public init(volume: URL) throws {
        let toc = volume.appendingPathComponent(".TOC.plist")
        guard let data = try? Data(contentsOf: toc) else { throw ReadError.notAnAudioCD(volume) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: volume.path)) ?? []
        try self.init(tocPlist: data, volume: volume, fileNames: names)
    }

    /// The table of contents in the form cddafs leaves it. Separate from the volume, so
    /// it can be checked on a saved table, without a disc in the drive.
    public init(tocPlist: Data, volume: URL, fileNames: [String]) throws {
        guard let root = try PropertyListSerialization.propertyList(from: tocPlist, format: nil) as? [String: Any],
              let sessions = root["Sessions"] as? [[String: Any]]
        else { throw ReadError.notAnAudioCD(volume) }

        struct Entry { let point: Int; let start: Int; let isData: Bool; let session: Int }
        var entries: [Entry] = []
        var leadouts: [Int: Int] = [:]
        for session in sessions {
            let number = session["Session Number"] as? Int ?? 1
            if let leadout = session["Leadout Block"] as? Int { leadouts[number] = leadout }
            for track in session["Track Array"] as? [[String: Any]] ?? [] {
                guard let point = track["Point"] as? Int, let start = track["Start Block"] as? Int else { continue }
                entries.append(Entry(point: point, start: start, isData: track["Data"] as? Bool ?? false,
                                     session: track["Session Number"] as? Int ?? number))
            }
        }
        entries.sort { $0.point < $1.point }
        guard let lastAudio = entries.last(where: { !$0.isData }) else { throw ReadError.noAudioTracks }

        // Track files: cddafs names them "<number> <name>.aiff".
        var files: [Int: URL] = [:]
        for name in fileNames where name.lowercased().hasSuffix(".aiff") {
            if let match = name.firstMatch(of: /^(\d+)\s/), let number = Int(match.1) {
                files[number] = volume.appendingPathComponent(name)
            }
        }

        // End of the last audio track: the start of the next track in the
        // same session, or the session's lead-out.
        var tracks: [Track] = []
        for (index, entry) in entries.enumerated() where !entry.isData {
            let next = entries.indices.contains(index + 1) && entries[index + 1].session == entry.session
                ? entries[index + 1].start : (leadouts[entry.session] ?? entry.start)
            tracks.append(Track(number: entry.point, startSector: entry.start,
                                sectorCount: max(0, next - entry.start), file: files[entry.point]))
        }

        // Disc ID according to MusicBrainz: on an "Enhanced CD" the data track in the second
        // session is not part of the hash, and the lead-out is its start minus 11,400
        // sectors (the gap between sessions).
        let counted = entries.filter { $0.point <= lastAudio.point }
        let trailingData = entries.first { $0.isData && $0.point > lastAudio.point }
        let leadout = trailingData.map { $0.start - 11_400 } ?? leadouts[lastAudio.session] ?? 0

        self.volume = volume
        self.volumeName = volume.lastPathComponent
        self.tracks = tracks
        self.discIDFirst = counted.first?.point ?? 1
        self.discIDLast = lastAudio.point
        self.discIDLeadout = leadout
        self.discIDOffsets = counted.map(\.start)
    }

    /// MusicBrainz Disc ID: SHA-1 of the first and last track, the lead-out
    /// and 99 offsets written in hex, then Base64 with ".", "_" and "-"
    /// instead of "+", "/" and "=". Computed locally - only the result goes to the network.
    public var discID: String {
        var text = String(format: "%02X%02X%08X", discIDFirst, discIDLast, discIDLeadout)
        var offsets = [Int](repeating: 0, count: 99)
        for (index, offset) in discIDOffsets.enumerated() where index < 99 { offsets[index] = offset }
        for offset in offsets { text += String(format: "%08X", offset) }
        let digest = Insecure.SHA1.hash(data: Data(text.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
    }

    /// The table of contents for the `toc=` query: when the disc with this Disc ID is not in the database,
    /// MusicBrainz looks for releases with the same track lengths.
    public var tocQuery: String {
        ([discIDFirst, discIDLast, discIDLeadout] + discIDOffsets).map(String.init).joined(separator: "+")
    }

    /// Whether macOS gave the disc a name (CD-TEXT or an earlier recognition).
    public var hasTitle: Bool { volumeName != "Audio CD" }

    /// The track title from the file name, if the file has a real name.
    public func fileTitle(of track: Track) -> String? {
        guard let name = track.file?.deletingPathExtension().lastPathComponent else { return nil }
        let title = name.replacing(/^\d+\s+/, with: "")
        return title == "Audio Track" || title.isEmpty ? nil : title
    }
}
