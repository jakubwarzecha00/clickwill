import Foundation

/// Exclusive writing to one iPod - across processes (the app, `ipodctl`).
///
/// Two writes at once to the same iPod (it happened with two `ipodctl copy` runs)
/// each assemble the database from their own read, so only one would win,
/// and the other's files would be left without entries. An `flock` lock on a file on the
/// Mac side; the system releases it by itself when the process ends, even on a crash.
public final class DeviceWriteLock: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    /// Takes the lock or throws immediately - without waiting for someone else's write.
    public static func acquire(identity: String, in directory: URL) throws -> DeviceWriteLock {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(identity).lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { throw ITDBError.writeRefused(.inconsistent("can't create the lock \(path)")) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw ITDBError.writeRefused(.anotherWriter)
        }
        return DeviceWriteLock(descriptor: descriptor)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

extension SnapshotStore {
    /// The write lock for a device, kept next to its backups.
    public func writeLock(for device: IPodDevice) throws -> DeviceWriteLock {
        try DeviceWriteLock.acquire(identity: device.identity, in: root)
    }
}
