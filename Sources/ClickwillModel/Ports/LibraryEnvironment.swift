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
    public var isMusicRunning: @Sendable () -> Bool

    public init(files: any FileSystem = LocalFileSystem(),
                backups: @escaping @Sendable () throws -> SnapshotStore,
                orderIntents: @escaping @Sendable () throws -> OrderIntentStore,
                isMusicRunning: @escaping @Sendable () -> Bool) {
        self.files = files
        self.backups = backups
        self.orderIntents = orderIntents
        self.isMusicRunning = isMusicRunning
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
            isMusicRunning: { false })
    }
}
