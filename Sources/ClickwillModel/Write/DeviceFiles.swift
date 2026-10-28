import Foundation

/// Rules for music files on the iPod.
enum DeviceFiles {
    /// A regular file (not a folder, not a link) lying canonically inside
    /// `Music`. Only such a file may be deleted - the path comes from the iPod database,
    /// so it can point anywhere.
    static func isDeletableAudioFile(_ url: URL, under music: URL, files: any FileSystem) -> Bool {
        guard files.isRegularFile(at: url) else { return false }
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root = music.standardizedFileURL.resolvingSymlinksInPath().path
        return canonical.hasPrefix(root + "/")
    }
}
