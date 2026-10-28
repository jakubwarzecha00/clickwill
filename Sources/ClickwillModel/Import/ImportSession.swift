import Foundation
import ITDBKit

/// The add sheet without a view: files with their albums, duplicates, albums already
/// on the iPod and the user's decisions. The sheet draws this and passes on
/// clicks; what goes into the queue after "Add" is computed by the session - and it has tests for that.
///
/// A value: the sheet keeps it in `@State`. Where the library is needed
/// (an album already on the iPod, its fields), the methods get the model as a parameter.
public struct ImportSession: Sendable {

    /// What to do with a group of files that matches an album already on the iPod.
    public enum AlbumChoice: Hashable, Sendable {
        /// The files replace the files of the same tracks of the album (the default).
        case replace
        /// The album stays as it is.
        case skip
        /// A separate album next to the current one.
        case separate
    }

    /// An album from the import that replaces the files of an album already on the iPod.
    public struct Replacement: Sendable {
        public let album: ImportAlbum
        public let match: AlbumMatch
    }

    /// A notice above the file list. The app builds the sentence.
    public enum Note: Sendable {
        /// The file could not be loaded.
        case unreadable(any Error)
        /// The iPod will not play this file, and it cannot be transcoded.
        case cannotPlay(title: String, reason: String?)
        /// The chosen artwork image cannot be read.
        case unreadableCover(URL)
    }

    public private(set) var candidates: [AudioImport.Candidate] = []
    /// Files that cannot be added, and other notices - the sheet shows them.
    public private(set) var problems: [Note] = []
    /// Groups matching an album already on the iPod - by titles
    /// and lengths, not by tags (`LibraryModel.matchingAlbum`).
    public private(set) var matches: [UUID: AlbumMatch] = [:]
    /// Album membership is decided once, when loading. Grouping by
    /// the name alone would fall apart while typing - the album would split into
    /// as many groups as the typed text has intermediate states.
    private var groupOf: [UUID: UUID] = [:]
    /// What is already on the iPod and in the queue - collected once, when opening.
    private let existing: SongIndex
    /// Tracks that already exist, but the user wants to add them anyway.
    private var addAnyway: Set<UUID> = []
    private var choices: [UUID: AlbumChoice] = [:]

    public init(existing: SongIndex) {
        self.existing = existing
    }

    // MARK: - Loading

    /// Adds loaded files. The same file a second time is not duplicated; a file
    /// goes to the group of the first earlier file with the same album;
    /// a file the iPod will not play and that cannot be transcoded goes
    /// to the notices instead of the list.
    public mutating func add(_ found: [AudioImport.Candidate], problems foundProblems: [any Error]) {
        let known = Set(candidates.map(\.url))
        let fresh = found.filter { !known.contains($0.url) }
        // The first track of a given album lends the group its identifier.
        var byKey: [AlbumKey: UUID] = [:]
        for candidate in candidates { byKey[candidate.draft.albumKey] = group(of: candidate) }
        for candidate in fresh {
            let key = candidate.draft.albumKey
            let group = byKey[key] ?? candidate.id
            byKey[key] = group
            groupOf[candidate.id] = group
        }
        candidates += fresh.filter { !$0.isHopeless }
        problems += foundProblems.map(Note.unreadable)
            + fresh.filter(\.isHopeless).map { .cannotPlay(title: $0.draft.title, reason: $0.verdict.reason) }
    }

    /// Recomputes the matches with albums on the iPod - after loading and after every
    /// change to the file list.
    @MainActor public mutating func refreshMatches(in model: LibraryModel) {
        var found: [UUID: AlbumMatch] = [:]
        for album in albums {
            if let match = model.matchingAlbum(for: album.songs) { found[album.id] = match }
        }
        matches = found
    }

    /// A file left out of adding ("Leave this file out").
    public mutating func remove(_ id: UUID) {
        candidates.removeAll { $0.id == id }
        addAnyway.remove(id)
    }

    /// A notice from outside loading, e.g. an artwork image that cannot be read.
    public mutating func note(_ problem: Note) {
        problems.append(problem)
    }

    // MARK: - Albums

    public var albums: [ImportAlbum] { ImportAlbum.grouping(candidates, groupOf: groupOf) }

    public func group(of candidate: AudioImport.Candidate) -> UUID { groupOf[candidate.id] ?? candidate.id }

    public func choice(for group: UUID) -> AlbumChoice { choices[group] ?? .replace }

    public mutating func choose(_ choice: AlbumChoice, for group: UUID) { choices[group] = choice }

    /// The track on the iPod that this file will replace - only with "Replace Files".
    public func replacedRow(_ candidate: AudioImport.Candidate) -> TrackRow? {
        let group = group(of: candidate)
        guard choice(for: group) == .replace else { return nil }
        return matches[group]?.pairs[candidate.id]
    }

    public var replacements: [Replacement] {
        albums.compactMap { album in
            guard let match = matches[album.id], choice(for: album.id) == .replace else { return nil }
            return Replacement(album: album, match: match)
        }
    }

    /// How many files on the iPod will get a new file.
    public var replaceCount: Int { replacements.reduce(0) { $0 + $1.match.pairs.count } }

    // MARK: - Duplicates

    /// Where this song already is - on the iPod or in the change queue.
    public func place(of candidate: AudioImport.Candidate) -> SongIndex.Place? {
        existing.place(of: candidate.draft)
    }

    public func isAddedAnyway(_ candidate: AudioImport.Candidate) -> Bool { addAnyway.contains(candidate.id) }

    public mutating func toggleAddAnyway(_ candidate: AudioImport.Candidate) {
        if addAnyway.contains(candidate.id) { addAnyway.remove(candidate.id) } else { addAnyway.insert(candidate.id) }
    }

    /// A duplicate the user did not add anyway.
    public func isSkipped(_ candidate: AudioImport.Candidate) -> Bool {
        place(of: candidate) != nil && !isAddedAnyway(candidate)
    }

    /// The "already there" control makes sense only outside a recognized album, or when
    /// deliberately adding a separate copy of the album.
    public func showsDuplicates(_ candidate: AudioImport.Candidate) -> Bool {
        let group = group(of: candidate)
        return matches[group] == nil || choice(for: group) == .separate
    }

    /// A dimmed row: a skipped duplicate or a whole skipped album.
    public func isLeftOut(_ candidate: AudioImport.Candidate) -> Bool {
        let group = group(of: candidate)
        if matches[group] != nil, choice(for: group) == .skip { return true }
        return showsDuplicates(candidate) && isSkipped(candidate)
    }

    /// Skipped as duplicates (outside recognized albums).
    public var skippedCount: Int { candidates.filter { showsDuplicates($0) && isSkipped($0) }.count }

    // MARK: - What goes into the queue

    /// What goes into the add queue. With a replacement only files without
    /// a counterpart on the iPod are added - attached to the existing album, not as a new one.
    @MainActor public func toAdd(in model: LibraryModel) -> [AudioImport.Candidate] {
        var result: [AudioImport.Candidate] = []
        for album in albums {
            if let match = matches[album.id] {
                switch choice(for: album.id) {
                case .skip:
                    continue
                case .replace:
                    guard let fields = model.albumFields(of: match.album) else { continue }
                    for var candidate in album.songs where match.extraCandidates.contains(candidate.id) {
                        candidate.draft.album = fields.album
                        candidate.draft.albumArtist = fields.albumArtist
                        candidate.draft.isCompilation = fields.isCompilation
                        if (candidate.draft.artist ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                            candidate.draft.artist = fields.artist ?? fields.albumArtist
                        }
                        result.append(candidate)
                    }
                    continue
                case .separate:
                    break
                }
            }
            result += album.songs.filter { !isSkipped($0) }
        }
        return result
    }

    /// The result of "Add": what could not be queued and how many files went onto
    /// the change list - the sheet shows refusals before closing.
    public struct Commit: Sendable {
        public let refused: [QueueRefusal]
        /// Files added or replaced.
        public let queued: Int
    }

    /// Queues the added files and replacements.
    @MainActor public func commit(to model: LibraryModel) -> Commit {
        let additions = toAdd(in: model)
        var refused = model.queueAdditions(additions)
        for replacement in replacements {
            refused += model.replaceFiles(replacement.album.songs, using: replacement.match)
        }
        // Each file gives at most one refusal.
        return Commit(refused: refused, queued: additions.count + replaceCount - refused.count)
    }

    // MARK: - Summary

    public var totalBytes: Int64 { candidates.reduce(0) { $0 + Int64($1.draft.sizeBytes) } }

    /// Files that must be transcoded before the write.
    public var converting: Int { candidates.filter { !$0.verdict.isSupported }.count }

    /// An album that is not on the iPod yet.
    @MainActor public func isNewAlbum(_ key: AlbumKey?, in model: LibraryModel) -> Bool {
        guard let key, !key.album.isEmpty else { return false }
        return !model.albums.contains { $0.title == key.album && $0.artist == key.albumArtist }
    }

    /// New albums that will go to the iPod without artwork. Existing ones are not counted -
    /// they keep theirs and nothing here affects them.
    @MainActor public func coverless(in model: LibraryModel) -> Int {
        albums.filter { album in
            isNewAlbum(album.songs.first?.draft.albumKey, in: model)
                && (matches[album.id] == nil || choice(for: album.id) == .separate)
                && album.songs.allSatisfy { $0.coverSource == nil }
        }.count
    }

    // MARK: - Corrections before the write

    /// A correction applies to what goes into the database, not to the file on disk - its
    /// tags are not touched.
    public func draft(of id: UUID) -> TrackDraft? { candidates.first { $0.id == id }?.draft }

    public mutating func edit(_ id: UUID, _ change: (inout TrackDraft) -> Void) {
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        change(&candidates[index].draft)
    }

    /// Album fields (name, album artist) apply to the whole group - otherwise
    /// a correction in one row would split the album in two.
    public func groupDraft(_ group: UUID) -> TrackDraft? {
        candidates.first { self.group(of: $0) == group }?.draft
    }

    public mutating func editGroup(_ group: UUID, _ change: (inout TrackDraft) -> Void) {
        for index in candidates.indices where self.group(of: candidates[index]) == group {
            change(&candidates[index].draft)
        }
    }

    /// The group's album artist, when one is entered.
    public func albumArtist(of group: UUID) -> String? {
        let trimmed = (groupDraft(group)?.albumArtist ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Whether any track of the group has a different artist than `artist`.
    public func songsDiffer(in group: UUID, from artist: String) -> Bool {
        candidates.contains { self.group(of: $0) == group && ($0.draft.artist ?? "") != artist }
    }

    /// Artwork applies to the whole album, not to a single track.
    public mutating func setCover(_ url: URL?, for group: UUID) {
        for index in candidates.indices where self.group(of: candidates[index]) == group {
            candidates[index].chosenCover = url
        }
    }
}
