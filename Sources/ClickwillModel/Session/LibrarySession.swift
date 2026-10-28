import Foundation
import ITDBKit

/// A library loaded from one source (a connected iPod or a backup from disk)
/// together with everything that follows from that load.
///
/// A new load is a whole new value (`open(_:)`), disconnecting the iPod
/// is its absence - no field remains from the previous source. Edits change
/// only `library` (and `artwork` when merging duplicates); a write replaces
/// the library and the database digest with what went to disk.
public struct LibrarySession: Sendable {
    public let source: LibrarySource
    public let paths: IPodPaths
    /// The library in memory, with edits applied that wait for the write.
    public internal(set) var library: ITLibrary
    public internal(set) var artwork: ArtworkLibrary?
    /// Digest of the database the edit started from - the write will refuse if
    /// the device already has a different one (e.g. Music rewrote it in the meantime).
    var sourceDigest: String
    /// Tracks whose file is not on the iPod.
    var missingFileIDs: Set<UInt32>
    /// Whether file presence can be checked - a backup from disk usually has no
    /// Music folder.
    public let canCheckFiles: Bool
    /// Format limits of the connected model. Without a device (a backup from disk)
    /// the Classic profile - the rules were measured on it - marked as assumed.
    public internal(set) var capabilities: IPodCapabilities
    /// The session reads and checks files through this file system.
    let files: any FileSystem

    public var device: IPodDevice? {
        if case .device(let device) = source { return device }
        return nil
    }

    /// Reads the database, artwork and file presence. Throws when the database cannot
    /// be read - then nothing is created that could get mixed up with the old
    /// source.
    public static func open(_ source: LibrarySource, files: any FileSystem = LocalFileSystem()) throws -> LibrarySession {
        let paths = try source.mount(using: files)
        let data = try files.contents(of: paths.iTunesDB)
        let library = try ITunesDBParser.parse(data)
        let artwork = try files.fileExists(at: paths.artworkDB)
            ? ArtworkDBParser.parse(try files.contents(of: paths.artworkDB)) : nil
        // On a real device a missing Music folder means all files are missing.
        let isDevice: Bool = { if case .device = source { return true } else { return false } }()
        let canCheck = isDevice || files.fileExists(at: paths.musicDirectory)
        let capabilities: IPodCapabilities = {
            if case .device(let device) = source { return IPodCapabilities.resolve(format: device.format, model: device.model) }
            var assumed = IPodCapabilities.classic
            assumed.isAssumed = true
            return assumed
        }()
        return LibrarySession(source: source, paths: paths, library: library, artwork: artwork,
                              sourceDigest: IPodDevice.digest(of: data),
                              missingFileIDs: canCheck ? missingFiles(in: library, paths: paths, files: files) : [],
                              canCheckFiles: canCheck, capabilities: capabilities, files: files)
    }

    /// The state after a successful write: the library as it went to disk, and the digest
    /// of the written database as the reference point for the next write.
    mutating func adopt(_ written: ITLibrary, sourceDigest: String, filesReplaced: Bool) {
        library = written
        self.sourceDigest = sourceDigest
        if filesReplaced { missingFileIDs = Self.missingFiles(in: written, paths: paths, files: files) }
    }

    static func missingFiles(in library: ITLibrary, paths: IPodPaths, files: any FileSystem) -> Set<UInt32> {
        Set(library.tracks.filter { track in
            guard let url = track.fileURL(on: paths) else { return true }
            return !files.fileExists(at: url)
        }.map(\.uniqueID))
    }
}
