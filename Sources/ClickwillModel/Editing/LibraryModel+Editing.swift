import Foundation
import CoreGraphics
import ITDBKit

/// Edit commands that the views call. Each hands the work to
/// `LibraryEditor` through `edit`, so the model takes over the result entirely or
/// not at all. Without a loaded library the commands do nothing. Only those
/// that can really refuse are `throws`.
extension LibraryModel {

    // MARK: - Metadata (MetadataEdits)

    public func renameTrack(_ row: TrackRow, in album: AlbumCard, to title: String) {
        edit { $0.renameTrack(row, in: album, to: title) }
    }

    public func setTrackNumber(_ row: TrackRow, in album: AlbumCard, to number: UInt32) {
        edit { $0.setTrackNumber(row, in: album, to: number) }
    }

    public func renumberTracks(in album: AlbumCard) throws {
        try edit { try $0.renumberTracks(in: album) }
    }

    /// Returns the card after the edit (the same identity, new fields).
    @discardableResult
    public func setAlbumField(_ album: AlbumCard, _ field: AlbumField, to value: String) throws -> AlbumCard {
        try edit { try $0.setAlbumField(album, field, to: value) }
        return current(album) ?? album
    }

    public func setCompilation(_ album: AlbumCard, _ flag: Bool) {
        edit { $0.setCompilation(album, flag) }
    }

    /// Merges the tracks of the `stray` card into the album `target`. Returns the card after the merge.
    @discardableResult
    public func mergeAlbum(_ stray: AlbumCard, into target: AlbumCard) -> AlbumCard {
        edit { $0.mergeAlbum(stray, into: target) }
        return current(stray) ?? current(target) ?? target
    }

    /// Other cards with the same title - an album split by a different album
    /// artist, the compilation flag or the `mhia` record.
    public func splitSiblings(of album: AlbumCard) -> [AlbumCard] {
        coverFlowAlbums.filter { $0.title == album.title && $0.id != album.id }
    }

    // MARK: - Order (OrderEdits)

    public func moveTracks(in album: AlbumCard, fromOffsets: IndexSet, toOffset: Int) throws {
        try edit { try $0.moveTracks(in: album, fromOffsets: fromOffsets, toOffset: toOffset) }
    }

    public func moveAlbumWithinGroup(_ album: AlbumCard, in group: CoverFlowGroup, toOffset: Int) throws {
        try edit { try $0.moveAlbumWithinGroup(album, in: group, toOffset: toOffset) }
    }

    // MARK: - Removal (RemovalEdits)

    public func deleteTrack(_ track: TrackRow, in album: AlbumCard, keepCopiesIn archive: URL? = nil) throws {
        let archive = archiveForRemoval(archive)
        try edit { try $0.deleteTrack(track, in: album, keepCopiesIn: archive) }
    }

    @discardableResult
    public func deleteAlbum(_ album: AlbumCard, keepCopiesIn archive: URL? = nil) throws -> Int {
        let archive = archiveForRemoval(archive)
        return try edit { try $0.deleteAlbum(album, keepCopiesIn: archive) } ?? 0
    }

    @discardableResult
    public func mergeDuplicates(_ groups: [DuplicateGroup], keepCopiesIn archive: URL? = nil) throws -> Int {
        let archive = archiveForRemoval(archive)
        return try edit { try $0.mergeDuplicates(groups, keepCopiesIn: archive) } ?? 0
    }

    /// On an experimental iPod a removed file is always copied to the Mac first: a backup
    /// holds the database and artwork, not the audio, so only the copy makes a removal reversible.
    private func archiveForRemoval(_ chosen: URL?) -> URL? {
        guard let device, device.writesOutsideConfirmedModels, device.writePolicy == .experimental else { return chosen }
        return chosen ?? environment.experimentalRemovalArchive
    }

    // MARK: - Artwork (ArtworkEdits)

    public func setArtwork(for album: AlbumCard, image: CGImage, sourceByteCount: UInt32 = 0) throws {
        try edit { try $0.setArtwork(for: album, image: image, sourceByteCount: sourceByteCount) }
    }

    /// Artwork from an image file (PNG, JPEG, HEIC...). The source size the
    /// iPod sees in the track records is the file size.
    public func setArtwork(for album: AlbumCard, imageFileAt url: URL) throws {
        let image = try Self.loadImage(at: url)
        let size = environment.files.size(of: url) ?? 0
        try setArtwork(for: album, image: image,
                       sourceByteCount: ITTrack.imageSourceByteCount(pictureBytes: UInt32(clamping: size)))
    }

    // MARK: - Files (FileEdits)

    public func importFile(_ candidate: ImportCandidate, for row: TrackRow, in album: AlbumCard) throws {
        try edit { try $0.importFile(candidate, for: row, in: album) }
    }

    public func replaceFile(_ candidate: ImportCandidate, for row: TrackRow, in album: AlbumCard) throws {
        try edit { try $0.replaceFile(candidate, for: row, in: album) }
    }

    public func cancelFileImport(_ trackID: UInt32) {
        edit { $0.cancelFileImport(trackID) }
    }

    public func convertTrack(_ row: TrackRow, in album: AlbumCard, keepOriginalsIn archiveDirectory: URL?) throws {
        try edit { try $0.convertTrack(row, in: album, keepOriginalsIn: archiveDirectory) }
    }

    /// Adds files to the add queue. Returns what cannot be added.
    @discardableResult
    public func queueAdditions(_ candidates: [AudioImport.Candidate]) -> [QueueRefusal] {
        edit { $0.queueAdditions(candidates) } ?? []
    }

    /// Adds files straight to an album, from the place `index` (nil = at the end).
    /// Returns what cannot be added.
    @discardableResult
    public func addFiles(_ urls: [URL], to album: AlbumCard, at index: Int?) async -> [QueueRefusal] {
        guard session != nil else { return [] }
        var read: [(url: URL, candidate: AudioImport.Candidate?)] = []
        for url in urls { read.append((url, try? await AudioImport.candidate(at: url, on: capabilities))) }
        return edit { $0.addFiles(read, to: album, at: index) } ?? []
    }

    /// Withdraws one track from the add queue before it reaches the iPod.
    public func removeQueuedAddition(_ id: UUID) {
        edit { $0.removeQueuedAdditions([id]) }
    }

    /// Withdraws a whole new album from the queue before it reaches the iPod.
    public func removeQueuedAlbum(_ album: PendingAlbum) {
        edit { $0.removeQueuedAdditions(Set(album.additions.map(\.id))) }
    }
}
