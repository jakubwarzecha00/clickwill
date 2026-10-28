import Foundation

/// One change waiting to be written. The list is a log for the user;
/// the change itself is already applied to the library in memory.
///
/// Field values before and after the change are raw - empty means "a field without
/// a value". How to phrase it is up to the app.
public struct PendingChange: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case albumMoved(album: String, from: Int, to: Int)
        case trackMoved(album: String, track: String, from: Int, to: Int)
        case trackDeleted(album: String, track: String, fileOnDisk: Bool)
        case compilationChanged(album: String, isCompilation: Bool, tracks: Int)
        case trackEdited(album: String, track: String, field: String, from: String, to: String)
        case albumEdited(album: String, field: String, from: String, to: String, tracks: Int)
        case tracksRenumbered(album: String, tracks: Int)
        case artworkReplaced(album: String, slots: Int, tracks: Int)
        case artworkAdded(album: String, tracks: Int)
        /// An album image for more tracks - a new image record per track.
        case artworkShared(album: String, tracks: Int)
        case albumMerged(album: String, artist: String, tracks: Int)
        case trackConverted(album: String, track: String, from: String, to: String, originalSaved: String?)
        case tracksAdded(tracks: Int, albums: Int, bytes: Int, converting: Int)
        case filesRestored(tracks: Int, albums: Int, converting: Int)
        /// Replacing the file of a track that already had one - separate from restoring,
        /// because it says something different: here something will disappear from the iPod after the write.
        case filesReplaced(tracks: Int, albums: Int, converting: Int)
        case albumDeleted(album: String, artist: String, tracks: Int, files: Int, copiesSaved: String?)
        /// Copies of the same song merged into one: `songs` of the removed copies,
        /// `files` that will disappear from the iPod.
        case duplicatesMerged(songs: Int, files: Int, copiesSaved: String?)
        /// Files the previous write did not delete - waiting for the next one.
        case filesLeftToDelete(files: Int)
    }
    public let id: UUID
    public let kind: Kind
    public let at: Date

    public init(_ kind: Kind) {
        self.id = UUID()
        self.kind = kind
        self.at = Date()
    }

    public var isDestructive: Bool {
        switch kind {
        case .trackDeleted, .albumDeleted, .duplicatesMerged, .filesLeftToDelete: return true
        default: return false
        }
    }
}
