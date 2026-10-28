import Foundation

/// A copy of a file from before conversion. Transcoding to a format the iPod plays
/// loses information relative to the source (24 bits -> 16), so the original must
/// land somewhere before it disappears from the device. No conversion flow touches
/// the file until the archive confirms the copy.
public enum OriginalArchive {

    public struct Entry: Sendable {
        public let url: URL
        public let sizeBytes: Int
    }

    /// File name: "Artist - Album - 05 Title.ext", without characters that
    /// break paths. A suffix resolves collisions.
    public static func fileName(artist: String?, album: String?, trackNumber: UInt32, title: String?, fileExtension: String) -> String {
        var parts: [String] = []
        if let artist, !artist.isEmpty { parts.append(artist) }
        if let album, !album.isEmpty { parts.append(album) }
        var last = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled"
        if trackNumber > 0 { last = String(format: "%02d %@", trackNumber, last) }
        parts.append(last)
        let name = parts.joined(separator: " - ")
        return sanitized(name) + (fileExtension.isEmpty ? "" : "." + fileExtension.lowercased())
    }

    /// Copies the file into the archive folder. Never overwrites anything: on a collision
    /// it appends " (2)", " (3)"... The folder is created if missing.
    public static func store(_ source: URL, in directory: URL, as name: String) throws -> Entry {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw ITDBError.writeRefused(.originalsFolderUnusable(directory))
            }
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard manager.isWritableFile(atPath: directory.path) else {
            throw ITDBError.writeRefused(.originalsFolderUnusable(directory))
        }
        let sourceSize = (try manager.attributesOfItem(atPath: source.path)[.size] as? Int) ?? 0
        if let free = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity,
           free < sourceSize {
            throw ITDBError.writeRefused(.notEnoughSpace(needed: Int64(sourceSize), available: Int64(free), on: .originalsFolder))
        }

        let base = (name as NSString).deletingPathExtension
        let suffix = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            let next = "\(base) (\(counter))" + (suffix.isEmpty ? "" : "." + suffix)
            candidate = directory.appendingPathComponent(next)
            counter += 1
            if counter > 999 { throw ITDBError.writeRefused(.inconsistent("too many copies named \(name)")) }
        }
        try manager.copyItem(at: source, to: candidate)

        // The copy must be complete - only then may the original be touched.
        let written = (try manager.attributesOfItem(atPath: candidate.path)[.size] as? Int) ?? -1
        guard written == sourceSize else {
            try? manager.removeItem(at: candidate)
            throw ITDBError.writeRefused(.inconsistent("the copy of the original has \(written) bytes instead of \(sourceSize)"))
        }
        return Entry(url: candidate, sizeBytes: written)
    }

    static func sanitized(_ text: String) -> String {
        var out = text
        for character in ["/", ":", "\\", "\0"] { out = out.replacingOccurrences(of: character, with: "-") }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix(".") { out = "_" + out.dropFirst() }
        // FAT/HFS: 255 characters per path component, with room for a collision suffix.
        if out.count > 200 { out = String(out.prefix(200)) }
        return out.isEmpty ? "Untitled" : out
    }
}
