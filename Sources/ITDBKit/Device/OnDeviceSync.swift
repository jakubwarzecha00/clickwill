import Foundation

/// A firmware that rebuilds iTunesDB on the iPod itself, from the folders on its disk:
/// iPod Classic FLAC OS (github.com/Valeria/IpodOS-Research), Apple's firmware 2.0.4 for the
/// iPod classic 7G with a library sync linked in. Read-only, like the Rockbox probe.
///
/// What it does, from the project's own documentation (`docs/CODEBASE.md`), not measured by us:
/// - At every boot and after every USB session it rewrites iTunesDB from `/Music/<album>/`
///   and `/TV Shows/<show>/`, signs it (hash58) and merges Play Counts.
/// - It owns every FLAC entry and every video located outside `iPod_Control`: it re-reads them
///   from their files, adds new files and drops entries whose file is gone. Every other entry
///   is kept as it was written, so songs Clickwill adds under `iPod_Control/Music` stay.
/// - It shows the covers of its own entries from `FLAC/covers.db`, built from a cover file in
///   the album folder or the picture inside the first FLAC - not from ArtworkDB.
///
/// So Clickwill can't remove an owned entry (the file stays in `/Music` and the entry comes
/// back) or change its cover, and an edit lasts only until its file changes.
public struct OnDeviceSync: Sendable, Equatable {
    /// The version in `FLAC/libsync.state`, written after every successful sync; `nil` when
    /// the file is missing or isn't one.
    public let stateVersion: Int?
    public let hasCoverCache: Bool
    public let hasLog: Bool
    /// Firmware images at the volume root (`osos-v18.dec`, `osos-update.dec` while an update waits).
    public let firmwareImages: [String]
    public let stateModified: Date?
    public let logModified: Date?

    public init(stateVersion: Int?, hasCoverCache: Bool, hasLog: Bool, firmwareImages: [String],
                stateModified: Date? = nil, logModified: Date? = nil) {
        self.stateVersion = stateVersion
        self.hasCoverCache = hasCoverCache
        self.hasLog = hasLog
        self.firmwareImages = firmwareImages
        self.stateModified = stateModified
        self.logModified = logModified
    }

    static let folder = "FLAC"
    static let stateFile = "libsync.state"
    static let coverFile = "covers.db"
    static let logFile = "rtlog.txt"
    static let magic = Array("FLSY".utf8)

    /// The track header's file type (`MhitLayout.fileTypeCode`).
    static let flacType: UInt32 = 0x464C_4143
    static let videoType: UInt32 = 0x4D34_5620
    /// 16 bytes in the zero tail of a 0x270-byte track header: `FLSY`, u16 version, u16 flags,
    /// u32 sync generation, u32 reserved. The Music app zeroes it.
    static let markerOffset = 0x258
    static let markerLength = 16

    /// `nil` when nothing on the volume belongs to it.
    public static func detect(at mountPoint: URL) -> OnDeviceSync? {
        let manager = FileManager.default
        let folder = mountPoint.appendingPathComponent(folder, isDirectory: true)
        func file(_ name: String) -> URL? {
            let url = folder.appendingPathComponent(name)
            return manager.fileExists(atPath: url.path) ? url : nil
        }
        let state = file(stateFile)
        let log = file(logFile)
        let covers = file(coverFile).flatMap { url -> Bool? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            return (try? handle.read(upToCount: 4)).map { Array($0) == Array("FCDB".utf8) }
        } ?? false
        let images = ((try? manager.contentsOfDirectory(atPath: mountPoint.path)) ?? [])
            .filter { $0.lowercased().hasPrefix("osos") && $0.lowercased().hasSuffix(".dec") }
            .sorted()
        guard state != nil || log != nil || covers || !images.isEmpty else { return nil }

        let version = state.flatMap { try? Data(contentsOf: $0) }.flatMap { data -> Int? in
            let bytes = Array(data.prefix(8))
            guard bytes.count >= 6, Array(bytes[0..<4]) == magic else { return nil }
            return Int(bytes[4]) | Int(bytes[5]) << 8
        }
        func modified(_ url: URL?) -> Date? {
            url.flatMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        }
        return OnDeviceSync(stateVersion: version, hasCoverCache: covers, hasLog: log != nil, firmwareImages: images,
                            stateModified: modified(state), logModified: modified(log))
    }

    /// Whether the sync rebuilds this entry from its file: every FLAC, and videos located
    /// outside `iPod_Control`.
    public static func manages(_ track: ITTrack) -> Bool {
        switch track.rawHeader[MhitLayout.fileTypeCode] {
        case flacType?: return true
        case videoType?:
            let parts = track.relativePath?.split(separator: "/") ?? []
            return parts.first?.caseInsensitiveCompare("iPod_Control") != .orderedSame
        default: return false
        }
    }

    /// The file of an entry the sync owns, anywhere on the volume (`Music/Album/01.flac`).
    /// `nil` for other entries - their file is only inside `iPod_Control/Music`.
    public static func file(of track: ITTrack, on paths: IPodPaths) -> URL? {
        guard manages(track), let relative = track.relativePath,
              let url = ContainedPath.resolve(relative, in: paths.mountPoint),
              ContainedPath.isInside(url, paths.containmentRoot) else { return nil }
        return url
    }

    /// The sync's mark in a track header.
    public enum Marker: Hashable, Sendable {
        case version(Int)
        /// All zero: written by the Music app, or never by the sync.
        case blank
        /// Something else in those bytes.
        case other
        /// A header too short to hold it.
        case none
    }

    public static func marker(of track: ITTrack) -> Marker {
        let header = track.rawHeader
        guard header.count >= markerOffset + markerLength else { return .none }
        let bytes = Array(header[markerOffset..<(markerOffset + markerLength)])
        if bytes.allSatisfy({ $0 == 0 }) { return .blank }
        guard Array(bytes[0..<4]) == magic else { return .other }
        return .version(Int(bytes[4]) | Int(bytes[5]) << 8)
    }
}
