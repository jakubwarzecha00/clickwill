import Foundation

/// A mounted volume that looks like an iPod.
public struct IPodVolume: Sendable, Hashable, Identifiable {
    public let paths: IPodPaths
    public let name: String
    public let totalCapacity: Int64
    public let availableCapacity: Int64
    public let isReadOnly: Bool
    /// Volume UUID from the moment it was opened. The mount path is not an identity:
    /// after a USB reset in the dock two iPods can come back with swapped
    /// names (`iPod` <-> `iPod 1`), even in the middle of copying.
    public var volumeUUID: String? = nil

    public var id: URL { paths.mountPoint }
    public var mountPoint: URL { paths.mountPoint }
    public var usedCapacity: Int64 { totalCapacity - availableCapacity }

    private static let volumeKeys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey, .volumeIsReadOnlyKey,
    ]

    /// Finds all mounted volumes containing an `iPod_Control` folder.
    public static func mounted() -> [IPodVolume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: volumeKeys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap(at)
    }

    /// The iPod at the given folder, if it is one - a volume or a plain folder
    /// (a fake in tests).
    public static func at(_ url: URL) -> IPodVolume? {
        let paths = IPodPaths(mountPoint: url)
        guard paths.looksLikeIPod else { return nil }
        let values = try? url.resourceValues(forKeys: Set(volumeKeys))
        return IPodVolume(
            paths: paths,
            name: values?.volumeName ?? url.lastPathComponent,
            totalCapacity: Int64(values?.volumeTotalCapacity ?? 0),
            availableCapacity: Int64(values?.volumeAvailableCapacity ?? 0),
            isReadOnly: values?.volumeIsReadOnly ?? false,
            volumeUUID: currentUUID(at: url)
        )
    }

    static func currentUUID(at mountPoint: URL) -> String? {
        var url = mountPoint
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    /// Throws when the same volume is no longer at the mount path -
    /// the iPod was unplugged or another one took its place. Called before every file
    /// and before the database write: the write must stop, not land on a second iPod.
    public func ensureStillMounted() throws {
        guard FileManager.default.fileExists(atPath: paths.control.path) else {
            throw ITDBError.writeRefused(.deviceGone)
        }
        guard let expected = volumeUUID else { return }
        guard Self.currentUUID(at: mountPoint) == expected else {
            throw ITDBError.writeRefused(.deviceSwapped)
        }
    }

    /// The first iPod found. Throws if there is none.
    public static func requireFirst() throws -> IPodVolume {
        guard let volume = mounted().first else { throw ITDBError.noIPodFound }
        return volume
    }
}
