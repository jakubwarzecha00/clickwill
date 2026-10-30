import Foundation
import ITDBKit

/// What the model needs from outside the iPod itself: the file system, where to keep
/// backups, where to remember the intended album order and how
/// to check whether Music is running.
///
/// The app uses `.standard` (the Mac's disk, folders in `~/Library/Application
/// Support`, a real Music check). Tests pass a temporary folder
/// and a fixed answer, so they do not touch the user's backups and do not depend on
/// what is open on the Mac.
public struct LibraryEnvironment: Sendable {
    public var files: any FileSystem
    public var backups: @Sendable () throws -> SnapshotStore
    public var orderIntents: @Sendable () throws -> OrderIntentStore
    /// Which GUID belongs to which database (`DeviceAliasStore`).
    public var deviceAliases: @Sendable () throws -> DeviceAliasStore
    public var isMusicRunning: @Sendable () -> Bool
    /// Where files removed from an experimental iPod are copied first
    /// (`LibraryModel.deleteTrack`).
    public var experimentalRemovalArchive: URL

    public init(files: any FileSystem = LocalFileSystem(),
                backups: @escaping @Sendable () throws -> SnapshotStore,
                orderIntents: @escaping @Sendable () throws -> OrderIntentStore,
                deviceAliases: @escaping @Sendable () throws -> DeviceAliasStore = { try DeviceAliasStore.standard() },
                isMusicRunning: @escaping @Sendable () -> Bool,
                experimentalRemovalArchive: URL = CDRipper.defaultRoot
                    .appendingPathComponent("Removed from Experimental iPods", isDirectory: true)) {
        self.files = files
        self.backups = backups
        self.orderIntents = orderIntents
        self.deviceAliases = deviceAliases
        self.isMusicRunning = isMusicRunning
        self.experimentalRemovalArchive = experimentalRemovalArchive
    }

    public static let standard = LibraryEnvironment(
        backups: { try SnapshotStore.standard() },
        orderIntents: { try OrderIntentStore.standard() },
        isMusicRunning: IPodDevice.isMusicRunning)

    /// Everything in one folder, Music always closed.
    public static func isolated(in directory: URL) -> LibraryEnvironment {
        LibraryEnvironment(
            backups: { SnapshotStore(root: directory.appendingPathComponent("Backups", isDirectory: true)) },
            orderIntents: { OrderIntentStore(root: directory.appendingPathComponent("Devices", isDirectory: true)) },
            deviceAliases: { DeviceAliasStore(file: directory.appendingPathComponent("Devices/identities.json")) },
            isMusicRunning: { false },
            experimentalRemovalArchive: directory.appendingPathComponent("Removed", isDirectory: true))
    }
}
