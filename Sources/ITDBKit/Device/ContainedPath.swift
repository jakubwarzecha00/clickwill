import Foundation

/// Paths from iPod data (`iTunesDB`, `ArtworkDB`) and from a backup manifest are not
/// trusted. A crafted database could point to `..` or a symbolic link
/// and lead a read, write or delete outside the iPod (security audit
/// 0.1.3: artwork, tracks, backup restore). Every file URL built from
/// such data goes through here.
public enum ContainedPath {

    /// Components of a relative path. `nil` when any of them is empty, `.`, `..`
    /// or contains a null character - such a path is never built at all.
    public static func components(_ relative: String) -> [String]? {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else { return nil }
        return parts
    }

    /// Whether `url`, after resolving symbolic links, lies inside `directory`
    /// (also resolved). A link in a parent folder or at the very
    /// end that leads outside gives `false`.
    public static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        return target.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// `relative` appended to `directory`, if the result stays inside.
    public static func resolve(_ relative: String, in directory: URL) -> URL? {
        guard let parts = components(relative) else { return nil }
        let url = parts.reduce(directory) { $0.appendingPathComponent($1) }
        return isInside(url, directory) ? url : nil
    }
}

extension IPodPaths {

    /// The track file from the location field in the database (`iPod_Control/Music/F05/ABCD.m4a`),
    /// only inside this iPod's `iPod_Control/Music`.
    public func musicFile(_ relative: String) -> URL? {
        guard let parts = ContainedPath.components(relative), parts.count >= 3,
              parts[0].caseInsensitiveCompare("iPod_Control") == .orderedSame,
              parts[1].caseInsensitiveCompare("Music") == .orderedSame,
              ContainedPath.isInside(musicDirectory, containmentRoot) else { return nil }
        return ContainedPath.resolve(parts.dropFirst(2).joined(separator: "/"), in: musicDirectory)
    }

    /// The artwork image file named in `ArtworkDB`: a bare name of the form
    /// `F<format>_<n>.ithmb`, only in this iPod's `iPod_Control/Artwork`.
    public func artworkFile(_ name: String) -> URL? {
        guard name.range(of: #"^F[0-9]{1,6}_[0-9]{1,4}\.ithmb$"#, options: [.regularExpression, .caseInsensitive]) != nil,
              ContainedPath.isInside(artworkDirectory, containmentRoot) else { return nil }
        return ContainedPath.resolve(name, in: artworkDirectory)
    }
}
