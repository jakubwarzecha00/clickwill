import Foundation

/// A comparison of what the database declares with what actually lies on disk.
public struct IntegrityReport: Sendable {

    public struct MissingFile: Sendable {
        public let uniqueID: UInt32
        public let title: String
        public let artist: String
        public let path: String
    }

    public struct SizeMismatch: Sendable {
        public let uniqueID: UInt32
        public let title: String
        public let path: String
        public let declared: UInt32
        public let actual: UInt64
    }

    public struct DanglingReference: Sendable {
        public let playlist: String
        public let trackID: UInt32
    }

    /// An entry in the database points to a file that does not exist.
    public let missingFiles: [MissingFile]
    /// A file lies in `Music/`, but no entry uses it.
    public let orphanedFiles: [String]
    /// An entry without a path - there is no telling what it refers to.
    public let locationlessTracks: [UInt32]
    /// The size in the database does not match the file size.
    public let sizeMismatches: [SizeMismatch]
    /// A playlist points to a track that is not in the database.
    public let danglingReferences: [DanglingReference]

    public let trackCount: Int
    public let audioFileCount: Int
    /// Entries of the iPod's own library sync whose file lies outside `iPod_Control`
    /// (`OnDeviceSync`) - found, so not missing.
    public var syncedFiles = 0

    public var isClean: Bool {
        missingFiles.isEmpty && orphanedFiles.isEmpty && locationlessTracks.isEmpty
            && sizeMismatches.isEmpty && danglingReferences.isEmpty
    }

    /// Extensions the iPod Classic can play.
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "m4p", "aa", "aif", "aiff", "wav"]

    public static func build(library: ITLibrary, paths: IPodPaths) throws -> IntegrityReport {
        let manager = FileManager.default
        let sync = OnDeviceSync.detect(at: paths.mountPoint)

        var missing: [MissingFile] = []
        var mismatches: [SizeMismatch] = []
        var locationless: [UInt32] = []
        var referenced: Set<String> = []
        var syncedCount = 0

        for track in library.tracks {
            guard let relative = track.relativePath else {
                locationless.append(track.uniqueID)
                continue
            }
            let synced = sync == nil ? nil : OnDeviceSync.file(of: track, on: paths)
            let url = synced ?? paths.musicFile(relative)
            if let url, synced == nil { referenced.insert(url.standardizedFileURL.path) }

            guard let url, let attributes = try? manager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? UInt64
            else {
                missing.append(
                    MissingFile(
                        uniqueID: track.uniqueID,
                        title: track.title ?? "",
                        artist: track.artist ?? "",
                        path: relative
                    )
                )
                continue
            }
            if synced != nil { syncedCount += 1 }
            if size != UInt64(track.sizeBytes) {
                mismatches.append(
                    SizeMismatch(
                        uniqueID: track.uniqueID,
                        title: track.title ?? "",
                        path: relative,
                        declared: track.sizeBytes,
                        actual: size
                    )
                )
            }
        }

        // Audio files in Music/ that nothing leads to.
        var orphaned: [String] = []
        var audioCount = 0
        // No `.skipsHiddenFiles`: the `F00`-`F49` folders have the hidden flag on the iPod,
        // so that option would cut out all the music.
        if let walker = manager.enumerator(
            at: paths.musicDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) {
            for case let url as URL in walker {
                guard !url.lastPathComponent.hasPrefix(".") else { continue }
                guard audioExtensions.contains(url.pathExtension.lowercased()) else { continue }
                audioCount += 1
                let path = url.standardizedFileURL.path
                if !referenced.contains(path) {
                    orphaned.append(String(path.dropFirst(paths.mountPoint.path.count + 1)))
                }
            }
        }

        let knownIDs = Set(library.tracks.map(\.uniqueID))
        var dangling: [DanglingReference] = []
        for playlist in library.playlists {
            for entry in playlist.entries where !knownIDs.contains(entry.trackID) {
                dangling.append(
                    DanglingReference(playlist: playlist.name ?? "(untitled)", trackID: entry.trackID)
                )
            }
        }

        var report = IntegrityReport(
            missingFiles: missing,
            orphanedFiles: orphaned.sorted(),
            locationlessTracks: locationless,
            sizeMismatches: mismatches,
            danglingReferences: dangling,
            trackCount: library.tracks.count,
            audioFileCount: audioCount
        )
        report.syncedFiles = syncedCount
        return report
    }
}
