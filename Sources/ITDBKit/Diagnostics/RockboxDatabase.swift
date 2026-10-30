import Foundation

/// Rockbox's own music database (`tagcache`): what Rockbox lists under Database, built
/// from the files on the disk, never from iTunesDB. Read to tell whether the songs
/// Clickwill adds or removes have reached it.
///
/// Layout from Rockbox's `apps/tagcache.c`, checked on databases built by Rockbox's own
/// code (simulator and database tool for the iPod Video):
/// - `database_idx.tcd`: a 24-byte header (magic, data size, entry count, serial,
///   commit id, dirty) and fixed-size entries: one 32-bit field per tag, then the flags.
/// - `database_4.tcd`: the file names. A 12-byte header, then entries of tag length,
///   index id and the zero-terminated path. Index entries point into it by offset.
///
/// The magic's last byte is the database version and the number of tags changed between
/// releases, so the entry size is taken from the file. The file name tag (4) and the flags
/// (last field) sit at the same place in every version.
public struct RockboxDatabase: Sendable, Equatable {
    /// The last byte of the magic, `0x10` in Rockbox 4.0.
    public let version: Int
    public let entries: Int
    /// Entries Rockbox marked deleted when it found the file gone.
    public let deleted: Int
    public let commitID: Int
    public let dirty: Bool
    /// Paths of the entries not marked deleted, as Rockbox stores them (`/iPod_Control/Music/F00/ABCD.mp3`).
    public let paths: [String]

    public init(version: Int, entries: Int, deleted: Int, commitID: Int, dirty: Bool, paths: [String]) {
        self.version = version
        self.entries = entries
        self.deleted = deleted
        self.commitID = commitID
        self.dirty = dirty
        self.paths = paths
    }

    static let magicPrefix: UInt32 = 0x5443_4800
    static let masterHeaderLength = 24
    static let tagHeaderLength = 12
    static let filenameTag = 4
    static let deletedFlag: UInt32 = 0x0001

    public enum ReadError: Error, Equatable, CustomStringConvertible {
        case magic(UInt32)
        case layout(String)

        public var description: String {
            switch self {
            case .magic(let value): String(format: "unknown magic 0x%08X", value)
            case .layout(let detail): detail
            }
        }
    }

    /// `nil` when the folder has no `database_idx.tcd` - Rockbox hasn't built a database.
    public static func read(folder: URL) throws -> RockboxDatabase? {
        let index = folder.appendingPathComponent("database_idx.tcd")
        guard FileManager.default.fileExists(atPath: index.path) else { return nil }
        let names = (try? Data(contentsOf: folder.appendingPathComponent("database_\(filenameTag).tcd"))) ?? Data()
        return try parse(index: Data(contentsOf: index), filenames: names)
    }

    public static func parse(index: Data, filenames: Data) throws -> RockboxDatabase {
        let reader = ByteReader(index)
        let magic = try reader.u32(at: 0)
        guard magic & 0xFFFF_FF00 == magicPrefix else { throw ReadError.magic(magic) }
        let count = Int(try reader.u32(at: 8))
        let body = reader.count - masterHeaderLength
        guard count > 0 else {
            return RockboxDatabase(version: Int(magic & 0xFF), entries: 0, deleted: 0,
                                   commitID: Int(try reader.u32(at: 16)), dirty: try reader.u32(at: 20) != 0, paths: [])
        }
        guard body % count == 0, body / count >= (filenameTag + 2) * 4, (body / count) % 4 == 0 else {
            throw ReadError.layout("\(body) B of entries do not divide into \(count) entries")
        }
        let entryLength = body / count

        let names = ByteReader(filenames)
        guard names.count >= tagHeaderLength, try names.u32(at: 0) == magic else {
            throw ReadError.layout("database_\(filenameTag).tcd missing or of another version")
        }
        var paths: [String] = []
        var deleted = 0
        for entry in 0..<count {
            let offset = masterHeaderLength + entry * entryLength
            if try reader.u32(at: offset + entryLength - 4) & deletedFlag != 0 { deleted += 1; continue }
            let seek = Int(try reader.u32(at: offset + filenameTag * 4))
            let length = Int(try names.u32(at: seek))
            guard length > 0, seek + 8 + length <= names.count else {
                throw ReadError.layout("entry \(entry) points outside database_\(filenameTag).tcd")
            }
            let bytes = try names.slice((seek + 8)..<(seek + 8 + length)).prefix { $0 != 0 }
            paths.append(String(decoding: bytes, as: UTF8.self))
        }
        return RockboxDatabase(version: Int(magic & 0xFF), entries: count, deleted: deleted,
                               commitID: Int(try reader.u32(at: 16)), dirty: try reader.u32(at: 20) != 0, paths: paths)
    }
}
