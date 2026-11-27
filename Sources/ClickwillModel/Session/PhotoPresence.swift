import Foundation
import ITDBKit

/// Whether the loaded source holds photos. Only the folder is checked; the photo database
/// itself is not read yet.
public enum PhotoPresence: Sendable, Hashable {
    case none
    case present
    /// A backup from disk keeps the library and artwork, never photos.
    case notInBackup

    static func detect(for source: LibrarySource, paths: IPodPaths, files: any FileSystem) -> PhotoPresence {
        if case .snapshot = source { return .notInBackup }
        return files.fileExists(at: paths.photosDirectory) ? .present : .none
    }
}
