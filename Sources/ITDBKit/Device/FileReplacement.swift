import Foundation

/// Replacing an audio file on the device. The new file goes next to the old one, under
/// its own name in the same `Fxx` folder; the old one disappears only after a successful
/// database write, so stopping at any moment leaves a working iPod.
public enum FileReplacement {

    public struct Placement: Sendable {
        /// Path relative to the volume root, with slashes.
        public let relativePath: String
        public let url: URL
        public let sizeBytes: UInt32
    }

    /// Free space we leave on the iPod after copying a file - we do not
    /// fill it to zero. Decimal, as macOS counts - the message
    /// comes out as an even "50 MB".
    public static let spaceReserve: Int64 = 50_000_000

    /// Refusal when copying the file would leave less than `spaceReserve`.
    /// The space needed in the refusal includes the reserve - otherwise
    /// the message would say "1 KB needed, 1.6 MB free".
    static func spaceRefusal(fileSize: Int64, free: Int64) -> WriteRefusal? {
        let needed = fileSize + spaceReserve
        return free < needed ? .notEnoughSpace(needed: needed, available: free, on: .iPod(reserve: spaceReserve)) : nil
    }

    /// Copies a file to the device and returns its location. Does not touch the database.
    public static func place(_ source: URL, in paths: IPodPaths, preferredDirectory: String? = nil) throws -> Placement {
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: source.path)
        let size = (attributes[.size] as? Int) ?? 0
        guard size > 0 else { throw ITDBError.writeRefused(.emptySourceFile) }

        if let free = try? paths.mountPoint.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           let refusal = spaceRefusal(fileSize: Int64(size), free: Int64(free)) {
            throw ITDBError.writeRefused(refusal)
        }

        // Random, but only among folders the device already has. A fixed
        // F00-F49 range fit the Classic; the nano 2G has F00-F13.
        let preferred = preferredDirectory.flatMap { $0.range(of: #"^F[0-9]{1,3}$"#, options: .regularExpression) != nil ? $0 : nil }
        let directory = preferred ?? paths.existingMusicFolders().randomElement() ?? "F00"
        let target = paths.musicDirectory.appendingPathComponent(directory, isDirectory: true)
        try manager.createDirectory(at: target, withIntermediateDirectories: true)

        // A name like iTunes uses: four capital letters. We draw until we hit a free one.
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        var url: URL?
        for _ in 0..<64 {
            let name = String((0..<4).map { _ in letters.randomElement()! }) + "." + source.pathExtension.lowercased()
            let candidate = target.appendingPathComponent(name)
            if !manager.fileExists(atPath: candidate.path) { url = candidate; break }
        }
        guard let destination = url else { throw ITDBError.writeRefused(.inconsistent("no free file name in \(directory)")) }

        try manager.copyItem(at: source, to: destination)
        // The copy must be complete before the database points to it.
        let written = (try manager.attributesOfItem(atPath: destination.path)[.size] as? Int) ?? 0
        guard written == size else {
            try? manager.removeItem(at: destination)
            throw ITDBError.writeRefused(.inconsistent("the copy has \(written) bytes instead of \(size)"))
        }

        let relative = "iPod_Control/Music/\(directory)/\(destination.lastPathComponent)"
        return Placement(relativePath: relative, url: destination, sizeBytes: UInt32(clamping: size))
    }

    /// The `Fxx` folder holding the track's current file - the new one goes
    /// next to it, so the layout on disk does not drift.
    public static func directory(of relativePath: String?) -> String? {
        guard let parts = relativePath?.split(separator: "/"), parts.count >= 2 else { return nil }
        let candidate = String(parts[parts.count - 2])
        // Just the `Fxx` name - the path comes from the database, and `F..` or `F/x` would lead
        // the new file outside the Music folder (security audit 0.1.3).
        return candidate.range(of: #"^F[0-9]{1,3}$"#, options: .regularExpression) != nil ? candidate : nil
    }
}
