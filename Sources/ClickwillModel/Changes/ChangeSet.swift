import Foundation
import CoreGraphics
import ITDBKit

/// Everything waiting to be written to the iPod: the log for the user and the tasks
/// the write will carry out on the device.
///
/// The log and the tasks change only through the methods of this type, so
/// they cannot drift apart:
///
/// - a keyed task (album artwork, track conversion) has exactly one
///   entry - requesting it again replaces it;
/// - the add queue and the queue of files for entries each have one summary
///   entry, recomputed on every queue change;
/// - file deletions and redirects after a merge are described by the entry of the command that
///   requests them (removing a track, an album, merging duplicates);
/// - after a write only the tasks that did not go in remain, together with their
///   entries (`remaining(after:)`).
///
/// Name and order edits have no task - they are already applied to the library
/// in memory and have only an entry (`record`). Discarding changes means assigning
/// an empty one (`ChangeSet()`).
public struct ChangeSet: Sendable {
    /// The log for the user - the list in Pending Changes.
    public private(set) var log: [PendingChange] = []
    /// Tracks to add - files still on the Mac, copied during the write.
    public private(set) var additions: [PendingAddition] = []
    /// Files chosen for entries without a file, or in place of the current file.
    public private(set) var fileImports: [UInt32: PendingFileImport] = [:]
    /// Tracks to transcode.
    private(set) var conversions: [UInt32: ConversionJob] = [:]
    /// First artwork for albums - goes to the device before the database, because the database must
    /// point to it. Key: the album card identifier.
    private(set) var artworkAdditions: [AlbumID: ArtworkAdditionJob] = [:]
    /// An album image for more tracks (a new `mhii` per track, the same
    /// slices) - before the database, like first artwork. Key: the album card identifier.
    private(set) var artworkSharing: [AlbumID: ArtworkSharingJob] = [:]
    /// Artwork to overwrite in the `.ithmb` files after the database write.
    /// Key: the album card identifier.
    private(set) var artworkReplacements: [AlbumID: ArtworkReplacementJob] = [:]
    /// Files to delete after a successful write - never before.
    private(set) var filesToDelete: [URL] = []
    /// Files whose copy must reach the Mac before they disappear from the iPod. Deletion
    /// is the only operation a database backup does not undo - a backup holds
    /// the database and artwork, not the music.
    private(set) var archiveBeforeDelete: [URL: ArchivePlan] = [:]
    /// Merged duplicates, removed -> kept: pending plays
    /// from `Play Counts` (by `uniqueID`).
    private(set) var playCountRedirects: [UInt32: UInt32] = [:]
    /// Merged duplicates, removed -> kept: the image owner in `ArtworkDB`
    /// (by `persistentID`).
    private(set) var artworkOwnerRedirects: [UInt64: UInt64] = [:]
    /// The log entry of each keyed task.
    private var entries: [TaskKey: PendingChange.ID] = [:]

    /// A task that has one log entry.
    private enum TaskKey: Hashable {
        /// First artwork or a replacement - an album has one artwork at a time.
        case cover(AlbumID)
        case coverSharing(AlbumID)
        case conversion(UInt32)
    }

    public init() {}

    /// The add queue alone - this is how `ipodctl add` adds.
    public init(additions: [PendingAddition]) {
        self.additions = additions
        summarizeAdditions()
    }

    /// Nothing is waiting to be written - no log entry, no device task.
    public var isEmpty: Bool {
        log.isEmpty && additions.isEmpty && fileImports.isEmpty && conversions.isEmpty
            && artworkAdditions.isEmpty && artworkSharing.isEmpty && artworkReplacements.isEmpty
            && filesToDelete.isEmpty && playCountRedirects.isEmpty && artworkOwnerRedirects.isEmpty
    }

    /// The write will put files on the iPod before the database - then preflight
    /// and a backup come first.
    var touchesFilesBeforeDatabase: Bool {
        !artworkAdditions.isEmpty || !artworkSharing.isEmpty || !conversions.isEmpty
            || !additions.isEmpty || !fileImports.isEmpty
    }
}

// MARK: - In-memory changes

extension ChangeSet {

    /// A change already applied to the library in memory (a name, the order,
    /// a record removal, a merge) - only a log entry.
    mutating func record(_ kind: PendingChange.Kind) {
        log.append(PendingChange(kind))
    }

    /// Merged duplicates, removed -> kept: plays from `Play Counts`
    /// and the image owner. An earlier merge may have pointed to the copy
    /// that is now disappearing - we redirect it further.
    mutating func redirect(playCounts: [UInt32: UInt32], artworkOwners: [UInt64: UInt64]) {
        for (from, to) in playCountRedirects { if let next = playCounts[to] { playCountRedirects[from] = next } }
        playCountRedirects.merge(playCounts) { _, new in new }
        for (from, to) in artworkOwnerRedirects { if let next = artworkOwners[to] { artworkOwnerRedirects[from] = next } }
        artworkOwnerRedirects.merge(artworkOwners) { _, new in new }
    }
}

// MARK: - Adding tracks and files for entries

extension ChangeSet {

    /// Adds a track to the add queue. Returns the reason for a refusal, or `nil`.
    mutating func queueAddition(_ addition: PendingAddition) -> QueueRefusal.Reason? {
        if addition.isHopeless { return .cannotPlay(addition.verdict.reason) }
        if additions.contains(where: { $0.source == addition.source }) { return .alreadyQueued }
        additions.append(addition)
        summarizeAdditions()
        return nil
    }

    /// Withdraws tracks from the add queue before they reach the iPod.
    mutating func removeAdditions(_ ids: Set<UUID>) {
        additions.removeAll { ids.contains($0.id) }
        summarizeAdditions()
    }

    /// A file for an entry - restoring a missing one or replacing the current one.
    mutating func queueFileImport(_ job: PendingFileImport) {
        fileImports[job.id] = job
        summarizeFileImports()
    }

    mutating func cancelFileImport(_ trackID: UInt32) {
        fileImports[trackID] = nil
        summarizeFileImports()
    }

    /// One entry for the whole add queue - otherwise adding an album would flood
    /// the list with a dozen rows saying the same thing.
    private mutating func summarizeAdditions() {
        log.removeAll { if case .tracksAdded = $0.kind { true } else { false } }
        guard !additions.isEmpty else { return }
        let albums = Set(additions.map { $0.draft.album ?? "" })
        let bytes = additions.reduce(0) { $0 + Int($1.draft.sizeBytes) }
        record(.tracksAdded(tracks: additions.count, albums: albums.count,
                            bytes: bytes, converting: additions.filter(\.needsConversion).count))
    }

    /// One entry for restoring and one for replacing - these are two different promises
    /// to the user, because a replacement deletes something from the iPod.
    private mutating func summarizeFileImports() {
        log.removeAll {
            switch $0.kind {
            case .filesRestored, .filesReplaced: return true
            default: return false
            }
        }
        let restored = fileImports.values.filter { !$0.isReplacement }
        let replaced = fileImports.values.filter(\.isReplacement)
        if !restored.isEmpty {
            record(.filesRestored(tracks: restored.count, albums: Set(restored.map(\.album)).count,
                                  converting: restored.filter(\.needsConversion).count))
        }
        if !replaced.isEmpty {
            record(.filesReplaced(tracks: replaced.count, albums: Set(replaced.map(\.album)).count,
                                  converting: replaced.filter(\.needsConversion).count))
        }
    }
}

// MARK: - Device tasks, shared by the app and `ipodctl`

extension ChangeSet {

    /// Queues the files of removed records for deletion after the write. A file
    /// goes in only when it is a regular file inside `Music`
    /// (`DeviceFiles.isDeletableAudioFile`) and no record that stays
    /// points to it - a path from the database is not trusted, and two records
    /// may share a file. The same file does not go in twice.
    ///
    /// - Parameters:
    ///   - removed: records that disappear from the database.
    ///   - library: the library after removal - the records that stay.
    ///   - archive: the folder for copies of files before deletion, named
    ///     "artist - album - number title"; `nil` - no copy.
    /// - Returns: files added to the queue.
    @discardableResult
    public mutating func queueFiles(of removed: [ITTrack], keeping library: ITLibrary, paths: IPodPaths,
                                    files: any FileSystem, keepCopiesIn archive: URL?) -> [URL] {
        let surviving = Set(library.tracks.compactMap(\.relativePath))
        var queued: [URL] = []
        for record in removed {
            guard let path = record.relativePath, !surviving.contains(path),
                  let url = record.fileURL(on: paths),
                  queueDeletion(of: url, under: paths, files: files) else { continue }
            if let archive {
                archiveBeforeDelete[url] = ArchivePlan(directory: archive, fileName: OriginalArchive.fileName(
                    artist: record.artist, album: record.album, trackNumber: record.trackNumber,
                    title: record.title, fileExtension: url.pathExtension))
            }
            queued.append(url)
        }
        return queued
    }

    /// Queues for deletion after the write the files in `Music` that no
    /// `library` record points to (for example after an interrupted add).
    /// The same rule as when removing tracks.
    /// - Returns: files added to the queue.
    @discardableResult
    public mutating func queueUnreferencedFiles(_ urls: [URL], in library: ITLibrary, paths: IPodPaths,
                                                files: any FileSystem) -> [URL] {
        let referenced = Set(library.tracks.compactMap { $0.fileURL(on: paths)?.standardizedFileURL.path })
        return urls.filter { url in
            !referenced.contains(url.standardizedFileURL.path) && queueDeletion(of: url, under: paths, files: files)
        }
    }

    /// Queues transcoding a track's file to a format the iPod plays.
    /// `fromLabel` describes the current format (empty when unknown).
    /// `archiveDirectory` is the folder for the original; `nil` is a deliberate consent to
    /// no copy - a 24 -> 16 bit conversion loses information.
    public mutating func queueConversion(trackID: UInt32, album: String, title: String, source: URL,
                                         to target: AudioCompatibility.Target, fromLabel: String,
                                         keepOriginalIn archiveDirectory: URL?) {
        conversions[trackID] = ConversionJob(trackID: trackID, album: album, title: title, source: source,
                                             target: target, fromLabel: fromLabel, archiveDirectory: archiveDirectory)
        replaceEntry(for: .conversion(trackID), with: .trackConverted(
            album: album, track: title, from: fromLabel, to: target.label, originalSaved: archiveDirectory?.path))
    }

    /// Queues the first artwork for an album without artwork: a new image for
    /// `owner`, a pointer in `mhia` and the marker in the album's tracks. Replaces
    /// artwork requested earlier for this album.
    /// `allowingUnverifiedFormats` is a hardware trial of an image format outside
    /// those confirmed on the device (`ipodctl artwork --add --unverified-formats`).
    public mutating func queueFirstCover(_ image: CGImage, sourceByteCount: UInt32, owner: ITTrack, tracks: [ITTrack],
                                         album: String, for key: AlbumID, allowingUnverifiedFormats: Bool = false) {
        artworkReplacements[key] = nil
        artworkAdditions[key] = ArtworkAdditionJob(album: album, ownerPersistentID: owner.persistentID,
                                                   trackIDs: tracks.map(\.persistentID), trackCount: tracks.count,
                                                   sourceByteCount: sourceByteCount, image: image,
                                                   allowingUnverifiedFormats: allowingUnverifiedFormats)
        replaceEntry(for: .cover(key), with: .artworkAdded(album: album, tracks: tracks.count))
    }

    /// Queues new pixels in place of the existing slices of an album's artwork.
    /// Replaces artwork requested earlier for this album.
    mutating func queueCoverReplacement(_ image: CGImage, slots: [ArtworkReplacement.Slot], trackIDs: [UInt64],
                                        album: String, for key: AlbumID) {
        artworkAdditions[key] = nil
        artworkReplacements[key] = ArtworkReplacementJob(album: album, slots: slots, trackIDs: trackIDs, image: image)
        replaceEntry(for: .cover(key), with: .artworkReplaced(album: album, slots: slots.count, tracks: trackIDs.count))
    }

    /// Queues the image `imageID` for more tracks of the album - one
    /// `mhii` per track, without new pixels. The nano 2G looks up artwork by the
    /// track's `persistentID`, so one record per album is enough only for
    /// the owner track.
    public mutating func queueCoverSharing(imageID: UInt32, with tracks: [ITTrack], album: String, for key: AlbumID) {
        artworkSharing[key] = ArtworkSharingJob(album: album, imageID: imageID, trackIDs: tracks.map(\.persistentID))
        replaceEntry(for: .coverSharing(key), with: .artworkShared(album: album, tracks: tracks.count))
    }

    /// A file to delete after the write, if allowed and not in the queue yet.
    private mutating func queueDeletion(of url: URL, under paths: IPodPaths, files: any FileSystem) -> Bool {
        guard DeviceFiles.isDeletableAudioFile(url, under: paths.musicDirectory, files: files),
              !filesToDelete.contains(url) else { return false }
        filesToDelete.append(url)
        return true
    }

    private mutating func replaceEntry(for key: TaskKey, with kind: PendingChange.Kind) {
        if let old = entries[key] { log.removeAll { $0.id == old } }
        let entry = PendingChange(kind)
        log.append(entry)
        entries[key] = entry.id
    }
}

// MARK: - After the write

extension ChangeSet {

    /// Tasks the write carried out, and files it did not delete.
    struct Completed {
        /// First artwork and artwork replacements.
        var covers: Set<AlbumID> = []
        var sharedCovers: Set<AlbumID> = []
        var conversions: Set<UInt32> = []
        var fileImports: Set<UInt32> = []
        var additions: Set<UUID> = []
        /// Files that could not be deleted for a temporary reason -
        /// they stay in the queue for the next write.
        var deletionsToRetry: [URL] = []
    }

    /// The queue after a successful database write: only the tasks that did not go in, with their
    /// log entries. Entries of changes that went with the database disappear, as do
    /// the redirects after a merge. Undeleted files get an entry of their own, because
    /// the command that requested them (a removal, a merge) has already run - without
    /// it the bar would say "nothing pending", and the files would vanish on the next,
    /// unrelated write.
    func remaining(after completed: Completed) -> ChangeSet {
        var next = ChangeSet()
        next.additions = additions.filter { !completed.additions.contains($0.id) }
        next.fileImports = fileImports.filter { !completed.fileImports.contains($0.key) }
        next.conversions = conversions.filter { !completed.conversions.contains($0.key) }
        next.artworkAdditions = artworkAdditions.filter { !completed.covers.contains($0.key) }
        next.artworkReplacements = artworkReplacements.filter { !completed.covers.contains($0.key) }
        next.artworkSharing = artworkSharing.filter { !completed.sharedCovers.contains($0.key) }
        next.filesToDelete = completed.deletionsToRetry
        next.archiveBeforeDelete = archiveBeforeDelete.filter { completed.deletionsToRetry.contains($0.key) }

        next.entries = entries.filter { next.has($0.key) }
        let kept = Set(next.entries.values)
        next.log = log.filter { kept.contains($0.id) }
        next.summarizeAdditions()
        next.summarizeFileImports()
        if !next.filesToDelete.isEmpty { next.record(.filesLeftToDelete(files: next.filesToDelete.count)) }
        return next
    }

    private func has(_ key: TaskKey) -> Bool {
        switch key {
        case .cover(let album): artworkAdditions[album] != nil || artworkReplacements[album] != nil
        case .coverSharing(let album): artworkSharing[album] != nil
        case .conversion(let track): conversions[track] != nil
        }
    }
}

/// Where a file's copy goes before it is deleted from the iPod.
struct ArchivePlan: Sendable {
    let directory: URL
    let fileName: String
}
