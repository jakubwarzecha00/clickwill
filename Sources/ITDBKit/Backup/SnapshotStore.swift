import Foundation
import CryptoKit

/// Backups of the database and artwork, kept on the Mac's disk.
///
/// The rule that applies throughout the app: no write to the iPod happens
/// without a fresh backup. The `iTunes` and `Artwork` folders together weigh a few dozen
/// megabytes, so hundreds of backups can be kept.
public struct SnapshotStore: Sendable {
    public let root: URL
    public let policy: SnapshotPolicy

    public init(root: URL, policy: SnapshotPolicy = .standard) {
        self.root = root
        self.policy = policy
    }

    /// `~/Library/Application Support/<product>/Backups`
    public static func standard(
        productName: String = ProductInfo.name,
        policy: SnapshotPolicy = .standard
    ) throws -> SnapshotStore {
        return SnapshotStore(
            root: try ProductInfo.supportDirectory(named: productName)
                .appendingPathComponent("Backups", isDirectory: true),
            policy: policy
        )
    }

    private func directory(forDevice guid: String) -> URL {
        root.appendingPathComponent(guid, isDirectory: true)
    }

    private func directory(forDevice guid: String, snapshot id: String) -> URL {
        directory(forDevice: guid).appendingPathComponent(id, isDirectory: true)
    }

    private func payloadDirectory(forDevice guid: String, snapshot id: String) -> URL {
        directory(forDevice: guid, snapshot: id).appendingPathComponent("files", isDirectory: true)
    }

    func manifestURL(forDevice guid: String, snapshot id: String) -> URL {
        directory(forDevice: guid, snapshot: id).appendingPathComponent("manifest.json")
    }

    // MARK: - Creating

    /// Copies `iTunes/` and `Artwork/` from the device and writes a manifest with checksums.
    ///
    /// Files identical to those in older backups are hard-linked instead of copied.
    /// Artwork weighs 32 MB and rarely changes, so each further backup usually costs
    /// about as much as the database alone.
    @discardableResult
    public func capture(from device: IPodDevice, reason: SnapshotReason, note: String? = nil) throws -> Snapshot {
        let createdAt = Date()
        // Identity, not GUID: older iPods do not have one, and they must be
        // entitled to backups just the same. The database identifier stands in for it.
        let guid = device.identity
        let manager = FileManager.default
        // The identifier has one-second precision. A second backup within the same second
        // (before files and before the database in one write) gets a number - otherwise
        // it would overwrite the first. The number is zero-padded so name order is preserved.
        let base = Snapshot.makeIdentifier(from: createdAt)
        var identifier = base
        var number = 1
        while manager.fileExists(atPath: directory(forDevice: guid, snapshot: identifier).path) {
            number += 1
            identifier = base + String(format: "-%02d", number)
        }
        let payload = payloadDirectory(forDevice: guid, snapshot: identifier)

        try manager.createDirectory(at: payload, withIntermediateDirectories: true)

        let reusable = try existingContentIndex(forDevice: guid)
        var entries: [Snapshot.Entry] = []
        var skipped: [Snapshot.Skipped] = []

        for directory in device.paths.backedUpDirectories {
            guard manager.fileExists(atPath: directory.path) else { continue }
            for source in try Self.regularFiles(in: directory) {
                let relative = try Self.relativePath(of: source, under: device.paths.control)

                if let exclusion = policy.exclusion(forFileNamed: source.lastPathComponent) {
                    skipped.append(
                        Snapshot.Skipped(
                            path: relative,
                            size: (try? Self.fileSize(of: source)) ?? 0,
                            reason: exclusion.reason
                        )
                    )
                    continue
                }

                let digest = try Self.sha256(of: source)
                let size = try Self.fileSize(of: source)
                let destination = payload.appendingPathComponent(relative)
                try manager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if manager.fileExists(atPath: destination.path) {
                    try manager.removeItem(at: destination)
                }

                var linked = false
                if let twin = reusable[digest], manager.fileExists(atPath: twin.path) {
                    // A link instead of a copy. Safe, because we never write into
                    // the backup folder - we only read from it when restoring.
                    do {
                        try manager.linkItem(at: twin, to: destination)
                        linked = true
                    } catch {
                        try manager.copyItem(at: source, to: destination)
                    }
                } else {
                    try manager.copyItem(at: source, to: destination)
                }

                entries.append(
                    Snapshot.Entry(path: relative, size: size, sha256: digest, linked: linked)
                )
            }
        }

        for required in policy.requiredPaths where !entries.contains(where: { $0.path == required }) {
            try? manager.removeItem(at: directory(forDevice: guid, snapshot: identifier))
            throw ITDBError.snapshotIncomplete(missing: required)
        }

        let snapshot = Snapshot(
            id: identifier,
            createdAt: createdAt,
            deviceGUID: guid,
            volumeName: device.volume.name,
            note: note,
            reason: reason,
            files: entries.sorted { $0.path < $1.path },
            skipped: skipped.sorted { $0.path < $1.path }
        )
        try write(snapshot)
        return snapshot
    }

    /// Map of `sha256 -> file in the store`, collected from this device's older backups.
    private func existingContentIndex(forDevice guid: String) throws -> [String: URL] {
        var index: [String: URL] = [:]
        for snapshot in (try? list(deviceGUID: guid)) ?? [] {
            let base = payloadDirectory(forDevice: guid, snapshot: snapshot.id)
            for entry in snapshot.files where index[entry.sha256] == nil {
                if let url = Self.contained(entry.path, in: base) { index[entry.sha256] = url }
            }
        }
        return index
    }

    private func write(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(
            to: manifestURL(forDevice: snapshot.deviceGUID, snapshot: snapshot.id),
            options: .atomic
        )
    }

    // MARK: - Reading

    /// Backups for a given device, newest first.
    public func list(deviceGUID: String) throws -> [Snapshot] {
        let deviceDirectory = directory(forDevice: deviceGUID)
        guard FileManager.default.fileExists(atPath: deviceDirectory.path) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contents = try FileManager.default.contentsOfDirectory(
            at: deviceDirectory, includingPropertiesForKeys: nil
        )
        return contents.compactMap { entry -> Snapshot? in
            let manifest = entry.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return nil }
            // The identifier and device from the manifest determine the backup folder we read
            // from, restore from and delete (including on our own, during cleanup). The manifest
            // is not trusted (security audit 0.1.3): it must name the folder it lies in.
            guard snapshot.id == entry.lastPathComponent, snapshot.deviceGUID == deviceGUID else { return nil }
            return snapshot
        }
        .sorted { $0.id > $1.id }
    }

    /// Backups filed under any of `deviceGUIDs` (`IPodDevice.identities`), newest first.
    public func list(deviceGUIDs: [String]) throws -> [Snapshot] {
        try deviceGUIDs.flatMap { try list(deviceGUID: $0) }.sorted { $0.id > $1.id }
    }

    public func snapshot(deviceGUIDs: [String], id: String) throws -> Snapshot {
        guard let match = try list(deviceGUIDs: deviceGUIDs).first(where: { $0.id == id }) else {
            throw ITDBError.snapshotNotFound(id)
        }
        return match
    }

    public func snapshot(deviceGUID: String, id: String) throws -> Snapshot {
        guard let match = try list(deviceGUID: deviceGUID).first(where: { $0.id == id }) else {
            throw ITDBError.snapshotNotFound(id)
        }
        return match
    }

    /// Checks that every file in the backup still has the checksum it had when created.
    public func verify(_ snapshot: Snapshot) throws {
        let payload = payloadDirectory(forDevice: snapshot.deviceGUID, snapshot: snapshot.id)
        for entry in snapshot.files {
            guard let url = Self.contained(entry.path, in: payload),
                  FileManager.default.fileExists(atPath: url.path),
                  try Self.sha256(of: url) == entry.sha256
            else {
                throw ITDBError.snapshotCorrupted(snapshot: snapshot.id, file: entry.path)
            }
        }
    }

    // MARK: - Restoring

    /// Filter for `restore`: artwork only, i.e. the first path component is `Artwork`.
    /// By components, not by string prefix (security audit 0.1.3).
    public static let artworkOnly: @Sendable (String) -> Bool = { ContainedPath.components($0)?.first == "Artwork" }

    /// A single folder name: no `/`, `.` or `..`.
    static func isName(_ name: String) -> Bool { ContainedPath.components(name)?.count == 1 }

    /// A backup file at a path from the manifest: only `iTunes/...` or
    /// `Artwork/...`, no `..`, and still inside `directory` after resolving links.
    static func contained(_ path: String, in directory: URL) -> URL? {
        guard let parts = ContainedPath.components(path), parts.count >= 2,
              ["iTunes", "Artwork"].contains(parts[0]) else { return nil }
        return ContainedPath.resolve(path, in: directory)
    }

    /// URL of a file stored in the backup, e.g. `iTunes/iTunesDB`.
    public func fileURL(in snapshot: Snapshot, path: String) -> URL {
        payloadDirectory(forDevice: snapshot.deviceGUID, snapshot: snapshot.id).appendingPathComponent(path)
    }

    /// The library stored in the backup - for previewing and restoring.
    public func readLibrary(of snapshot: Snapshot) throws -> ITLibrary {
        try ITunesDBParser.parse(try Data(contentsOf: fileURL(in: snapshot, path: "iTunes/iTunesDB")))
    }

    /// Restores a backup onto the device. Verifies checksums before every write,
    /// and each file lands next to its target first and only then takes over its name.
    ///
    /// `include` lets you restore only part of a backup - the app restores
    /// artwork this way, because the database goes through the regular write path with its gates.
    public func restore(_ snapshot: Snapshot, to device: IPodDevice,
                        include: (String) -> Bool = { _ in true }) throws {
        try verify(snapshot)
        let payload = payloadDirectory(forDevice: snapshot.deviceGUID, snapshot: snapshot.id)
        let manager = FileManager.default

        for entry in snapshot.files where include(entry.path) {
            // Paths from the manifest are not trusted (security audit 0.1.3): only
            // iTunes/ and Artwork/, no `..`, and inside the folder in both places.
            guard let source = Self.contained(entry.path, in: payload),
                  ContainedPath.isInside(device.paths.control, device.paths.mountPoint),
                  let destination = Self.contained(entry.path, in: device.paths.control) else {
                throw ITDBError.unsafePath(entry.path)
            }
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).restoring")
            if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
            try manager.copyItem(at: source, to: staging)
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        }

        // Artwork is a set: `ArtworkDB` and its `.ithmb` files. A backup from before
        // the first artwork (nano 2G after Finder) has none of them, and without
        // this a restore would leave the new `ArtworkDB` in place. Only
        // `Artwork/`: in `iTunes/` the iPod itself creates files (`Play Counts`),
        // and deleting them would erase listening history.
        let known = Set(snapshot.files.map(\.path) + snapshot.skipped.map(\.path))
        let artwork = device.paths.artworkDirectory
        guard manager.fileExists(atPath: artwork.path) else { return }
        for file in try Self.regularFiles(in: artwork) {
            let relative = try Self.relativePath(of: file, under: device.paths.control)
            guard include(relative), !known.contains(relative) else { continue }
            try manager.removeItem(at: file)
        }
    }

    /// Deletes backups older than the policy allows. Returns what was removed.
    ///
    /// An error with a single backup does not stop the cleanup and **is not an error
    /// of the whole operation** - cleanup runs after a successful write and has no right
    /// to undermine it. A backup that could not be deleted stays, and we will try
    /// again next time.
    @discardableResult
    public func prune(deviceGUID: String, retention: SnapshotRetention = .standard,
                      now: Date = Date()) -> [Snapshot] {
        prune(deviceGUIDs: [deviceGUID], retention: retention, now: now)
    }

    /// One retention over the backups of every name of one iPod - counted per name, the
    /// "keep the last N" rule would keep N of each.
    @discardableResult
    public func prune(deviceGUIDs: [String], retention: SnapshotRetention = .standard,
                      now: Date = Date()) -> [Snapshot] {
        guard let all = try? list(deviceGUIDs: deviceGUIDs) else { return [] }
        var removed: [Snapshot] = []
        for snapshot in retention.expired(among: all, now: now) {
            do { try delete(snapshot); removed.append(snapshot) } catch { continue }
        }
        return removed
    }

    public func delete(_ snapshot: Snapshot) throws {
        guard Self.isName(snapshot.deviceGUID), Self.isName(snapshot.id) else {
            throw ITDBError.unsafePath("\(snapshot.deviceGUID)/\(snapshot.id)")
        }
        try FileManager.default.removeItem(
            at: directory(forDevice: snapshot.deviceGUID, snapshot: snapshot.id)
        )
    }

    // MARK: - Helpers

    static func regularFiles(in directory: URL) throws -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    static func relativePath(of url: URL, under base: URL) throws -> String {
        let path = url.standardizedFileURL.path
        let prefix = base.standardizedFileURL.path + "/"
        guard path.hasPrefix(prefix) else { throw ITDBError.pathMissing(url) }
        return String(path.dropFirst(prefix.count))
    }

    static func fileSize(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    /// Streamed, because `F1060_1.ithmb` can be 27 MB.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).hexString
    }
}
