import Foundation

/// Operations on iPod files and backups from disk that the model needs:
/// reading the database, file presence, deletion after the write, backup links.
///
/// The single place with `FileManager` is `LocalFileSystem`. Tests pass a fake,
/// for example a disk that refuses to delete a file.
///
/// Import and ripping on the Mac (`AudioImport`, `CDImport`, `AudioFiles`) and
/// the core (`ITDBKit`) work with `FileManager` directly - they are the edge
/// of the file system, not the model.
public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    /// A regular file: it exists, is not a folder and is not a link.
    func isRegularFile(at url: URL) -> Bool
    func contents(of url: URL) throws -> Data
    /// Size in bytes; `nil` when there is no file.
    func size(of url: URL) -> Int64?
    func removeItem(at url: URL) throws
    func createDirectory(at url: URL) throws
    /// The link target; `nil` when it is not a link.
    func symbolicLinkDestination(at url: URL) -> String?
    func createSymbolicLink(at url: URL, to destination: URL) throws
    var temporaryDirectory: URL { get }
}

/// The Mac's disk and connected volumes through `FileManager.default`.
public struct LocalFileSystem: FileSystem {
    public init() {}

    private var manager: FileManager { .default }

    public func fileExists(at url: URL) -> Bool { manager.fileExists(atPath: url.path) }

    public func isDirectory(at url: URL) -> Bool {
        var directory: ObjCBool = false
        return manager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    public func isRegularFile(at url: URL) -> Bool {
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else { return false }
        return (attributes[.type] as? FileAttributeType) == .typeRegular
    }

    public func contents(of url: URL) throws -> Data { try Data(contentsOf: url) }

    public func size(of url: URL) -> Int64? {
        ((try? manager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value
    }

    public func removeItem(at url: URL) throws { try manager.removeItem(at: url) }

    public func createDirectory(at url: URL) throws {
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func symbolicLinkDestination(at url: URL) -> String? {
        try? manager.destinationOfSymbolicLink(atPath: url.path)
    }

    public func createSymbolicLink(at url: URL, to destination: URL) throws {
        try manager.createSymbolicLink(at: url, withDestinationURL: destination)
    }

    public var temporaryDirectory: URL { manager.temporaryDirectory }
}
