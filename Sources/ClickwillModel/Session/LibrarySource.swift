import Foundation
import ITDBKit

/// Where the app gets the library from: a connected iPod or a backup from disk.
///
/// A backup from disk exists so the interface can be developed and tested
/// without a connected iPod and without the risk of writing to the device.
public enum LibrarySource: Sendable, Hashable {
    case device(IPodDevice)
    case snapshot(URL)

    public var isWritable: Bool {
        if case .device(let device) = self { return device.supportsWriting }
        return false
    }

    public var displayName: String {
        switch self {
        case .device(let device): return device.volume.name
        case .snapshot(let url): return url.lastPathComponent
        }
    }

    /// Paths in the iPod layout.
    ///
    /// A connected iPod: its own. A backup from disk has a different layout (`files/iTunes`,
    /// `files/Artwork`), so here a folder **is created on the Mac's disk** in the temporary
    /// folder with links to it - the core reads it the same way as
    /// a real volume. Opening the session (`LibrarySession.open`) does this, once
    /// per load.
    public func mount(using files: any FileSystem = LocalFileSystem()) throws -> IPodPaths {
        switch self {
        case .device(let device):
            return device.paths
        case .snapshot(let root):
            let source = root.appendingPathComponent("files", isDirectory: true)
            // The folder name from the whole path, not from the last component - two backups
            // with the same name in different places must not share links.
            let key = IPodDevice.digest(of: Data(root.standardizedFileURL.path.utf8)).prefix(16)
            let mount = files.temporaryDirectory.appendingPathComponent("clickwill-snapshot-\(key)", isDirectory: true)
            // The older layout (the whole volume as a link to the backup folder) - into a plain folder.
            if files.symbolicLinkDestination(at: mount) != nil { try files.removeItem(at: mount) }
            let control = mount.appendingPathComponent("iPod_Control", isDirectory: true)
            try files.createDirectory(at: control)
            for name in ["iTunes", "Artwork"] {
                let link = control.appendingPathComponent(name)
                let target = source.appendingPathComponent(name)
                if files.symbolicLinkDestination(at: link) != target.path {
                    try? files.removeItem(at: link)
                    try files.createSymbolicLink(at: link, to: target)
                }
            }
            // The links lead to `files/`, so that is the boundary for pointers from the database.
            return IPodPaths(mountPoint: mount, containmentRoot: source)
        }
    }

    /// The write scope of the Mac release: alpha and beta write only to the iPod classic.
    /// Other models are read-only until there is demand.
    public static let writeScope: IPodDevice.WriteScope = .iPodClassic
}

extension IPodDevice: Hashable {
    public static func == (lhs: IPodDevice, rhs: IPodDevice) -> Bool {
        lhs.volume == rhs.volume && lhs.identity == rhs.identity
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(volume)
        hasher.combine(identity)
    }
}
