import Foundation

/// The folder layout on the iPod. Everything the app reads and writes
/// goes through this type - nowhere else do we build paths by hand.
public struct IPodPaths: Sendable, Hashable {
    public let mountPoint: URL
    /// The folder that track and artwork files named by the database cannot leave
    /// (`ContainedPath`). On the iPod it is the volume. A snapshot from disk assembles the volume
    /// from links into the backup folder, so there the boundary is that folder.
    public let containmentRoot: URL

    public init(mountPoint: URL, containmentRoot: URL? = nil) {
        self.mountPoint = mountPoint
        self.containmentRoot = containmentRoot ?? mountPoint
    }

    public var control: URL { mountPoint.appendingPathComponent("iPod_Control", isDirectory: true) }
    public var iTunesDirectory: URL { control.appendingPathComponent("iTunes", isDirectory: true) }
    public var artworkDirectory: URL { control.appendingPathComponent("Artwork", isDirectory: true) }
    public var musicDirectory: URL { control.appendingPathComponent("Music", isDirectory: true) }
    public var deviceDirectory: URL { control.appendingPathComponent("Device", isDirectory: true) }

    public var iTunesDB: URL { iTunesDirectory.appendingPathComponent("iTunesDB") }
    public var playCounts: URL { iTunesDirectory.appendingPathComponent("Play Counts") }
    public var artworkDB: URL { artworkDirectory.appendingPathComponent("ArtworkDB") }
    public var sysInfo: URL { deviceDirectory.appendingPathComponent("SysInfo") }
    public var sysInfoExtended: URL { deviceDirectory.appendingPathComponent("SysInfoExtended") }

    /// Folders covered by a backup - the whole database and all artwork.
    public var backedUpDirectories: [URL] { [iTunesDirectory, artworkDirectory] }

    /// The `Music/Fxx` folders that **exist** on the device - sorted.
    ///
    /// Their number depends on the generation (50 on a Classic 7G, F00-F49), and
    /// restoring the iPod creates them. We count them instead of taking them from a table: a new file goes
    /// only where the firmware already has its own.
    public func existingMusicFolders() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: musicDirectory.path)) ?? []
        return names.filter { name in
            guard name.count == 3, name.hasPrefix("F"), name.dropFirst().allSatisfy(\.isNumber) else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: musicDirectory.appendingPathComponent(name).path,
                                                  isDirectory: &isDirectory) && isDirectory.boolValue
        }.sorted()
    }

    /// Whether this volume looks like an iPod.
    public var looksLikeIPod: Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: control.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
