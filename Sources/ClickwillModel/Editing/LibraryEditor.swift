import Foundation
import CoreGraphics
import ITDBKit

/// The context of edit commands: the library in memory and the change queue that
/// a command changes, plus what a command only reads.
///
/// Commands are methods of this type, grouped in the `Editing/` files: metadata,
/// order, removal, artwork, files. Each applies its change to `library`
/// with core functions (the same ones the CLI has) and requests tasks through the methods
/// of `changes`, which keep the log themselves. None of them touches the device - only
/// the write does that.
///
/// A value, not an object: a command works on a copy, and `LibraryModel.edit`
/// takes over the result with a single assignment only when the command did not throw.
/// An error halfway through a command does not leave, for example, a file in the deletion queue
/// for a track that is still in the database.
struct LibraryEditor {
    var library: ITLibrary {
        didSet { libraryChanged = true }
    }
    var artwork: ArtworkLibrary? {
        didSet { artworkChanged = true }
    }
    var changes: ChangeSet
    /// The cards from before the edit - for finding the current version of a card from the view.
    let catalog: AlbumCatalog
    let paths: IPodPaths
    let files: any FileSystem
    /// A snapshot without a Music folder does not provide files.
    let canCheckFiles: Bool
    let missingFileIDs: Set<UInt32>
    let formatVerdicts: [UInt32: AudioCompatibility.Verdict]
    let formatLabels: [UInt32: String]

    /// Previews of artwork waiting to be written, by track identifier.
    private(set) var coverPreviews: [(image: CGImage, trackIDs: [UInt64])] = []
    /// Artwork moved to another track (merged duplicates).
    private(set) var coverOwners: [UInt64: UInt64] = [:]
    /// Whether the command changed the library - then the cards are rebuilt.
    private(set) var libraryChanged = false
    private(set) var artworkChanged = false

    init(session: LibrarySession, changes: ChangeSet, catalog: AlbumCatalog,
         formatVerdicts: [UInt32: AudioCompatibility.Verdict], formatLabels: [UInt32: String]) {
        self.library = session.library
        self.artwork = session.artwork
        self.changes = changes
        self.catalog = catalog
        self.paths = session.paths
        self.files = session.files
        self.canCheckFiles = session.canCheckFiles
        self.missingFileIDs = session.missingFileIDs
        self.formatVerdicts = formatVerdicts
        self.formatLabels = formatLabels
    }

    // MARK: - Shared

    /// The current version of a card - the view may hold a card from before the previous
    /// edit. `nil` when no track of the album is left.
    func current(_ album: AlbumCard) -> AlbumCard? { catalog.current(album) }

    /// The album title for the log - from the current card, if there is one.
    func title(of album: AlbumCard) -> String { current(album)?.title ?? album.title }

    /// Records of the current version of the card in display order; an album
    /// that no longer exists has no records.
    func records(of album: AlbumCard) -> [ITTrack] {
        guard let album = current(album) else { return [] }
        let all = library.tracks
        return album.trackIndices.compactMap { $0 < all.count ? all[$0] : nil }
    }

    func record(_ id: UInt32) -> ITTrack? { library.tracks.first { $0.uniqueID == id } }

    /// The URL of the track's audio file; `nil` without a Music folder.
    func fileURL(of id: UInt32) -> URL? {
        guard canCheckFiles else { return nil }
        return record(id)?.fileURL(on: paths)
    }

    mutating func recordChange(_ kind: PendingChange.Kind) { changes.record(kind) }

    mutating func preview(_ image: CGImage, for trackIDs: [UInt64]) { coverPreviews.append((image, trackIDs)) }

    mutating func reownCovers(_ owners: [UInt64: UInt64]) { coverOwners.merge(owners) { _, new in new } }
}

extension LibraryModel {

    /// Runs an edit command on a copy of the state and takes over the result when it
    /// succeeded. Without a loaded library it does nothing and returns `nil`.
    @discardableResult
    func edit<Result>(_ command: (inout LibraryEditor) throws -> Result) rethrows -> Result? {
        guard let session else { return nil }
        var editor = LibraryEditor(session: session, changes: changes, catalog: catalog,
                                   formatVerdicts: formatVerdicts, formatLabels: formatLabels)
        let result = try command(&editor)
        if editor.libraryChanged { replaceLibrary(editor.library) }
        if editor.artworkChanged { replaceArtwork(editor.artwork) }
        changes = editor.changes
        for preview in editor.coverPreviews { covers.show(preview.image, for: preview.trackIDs) }
        if !editor.coverOwners.isEmpty { covers.reown(editor.coverOwners) }
        if editor.libraryChanged { rebuildCards() }
        return result
    }
}
