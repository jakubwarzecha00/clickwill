import Foundation

/// Hooking a new track into the database structure: the `mhlt` list, both copies of the master
/// playlist, the browse tables with their jump bars, and the album list.
///
/// A new record goes **at the end** of the track list, and that alone makes the whole operation
/// safe: the browse tables hold record positions, so
/// appending at the end shifts no existing position. Only what we insert ourselves
/// changes. For the same reason `Play Counts`, which
/// is positional, stays consistent with the list.
extension ITLibrary {

    /// Adds tracks. Each must already have its file copied to the device.
    public func addingTracks(
        _ drafts: [TrackDraft], now: Date = Date(),
        persistentID: @Sendable () -> UInt64 = { UInt64.random(in: 1...UInt64.max) }
    ) throws -> ITLibrary {
        var result = self
        for draft in drafts {
            result = try result.addingTrack(draft, now: now, persistentID: persistentID)
        }
        return result
    }

    func addingTrack(
        _ draft: TrackDraft, now: Date, persistentID: @Sendable () -> UInt64
    ) throws -> ITLibrary {
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TrackInsertionError.emptyTitle
        }
        let existing = tracks
        guard !existing.contains(where: { $0.relativePath == draft.relativePath }) else {
            throw TrackInsertionError.pathAlreadyUsed(draft.relativePath)
        }
        guard let template = templateTrack(for: draft.kind) ?? crossKindTemplate(for: draft.kind) else {
            throw TrackInsertionError.noTemplate(draft.kind)
        }
        guard masterPlaylist != nil else { throw TrackInsertionError.noMasterPlaylist }

        // Random draws with retries, but bounded - the caller may pass
        // a constant generator, and then an unbounded loop would never end.
        let usedIDs = Set(existing.map(\.persistentID))
        var newPersistentID = persistentID()
        var attempts = 0
        while usedIDs.contains(newPersistentID) || newPersistentID == 0 {
            attempts += 1
            guard attempts < 16 else { throw TrackInsertionError.noFreePersistentID }
            newPersistentID = persistentID()
        }
        let uniqueID = (existing.map(\.uniqueID).max() ?? 0) + 1

        // Tracks of the same album hand over their sort fields - otherwise the new
        // track would split the album into two covers.
        let sibling = existing.first { $0.albumKey == draft.albumKey }

        let albums = self.albums
        let albumRecord = sibling.flatMap { s in albums.first { UInt32($0.index) == s.albumRecordIndex } }
        let newAlbumIndex = (albums.map { UInt32($0.index) }.max() ?? 0) + 1
        let albumRecordIndex = albumRecord.map { UInt32($0.index) } ?? newAlbumIndex

        let track = makingTrack(from: draft, template: template, uniqueID: uniqueID,
                                persistentID: newPersistentID, albumRecordIndex: albumRecordIndex,
                                inheritingSortFieldsFrom: sibling, now: now)

        let position = UInt32(existing.count)
        var updated = existing
        updated.append(track)

        var copy = self
        copy.sections = try sections.map { section in
            var changed = section
            switch section.content {
            case .tracks:
                changed.content = .tracks(updated)
            case .playlists(let playlists):
                changed.content = .playlists(try playlists.map { playlist in
                    guard playlist.isMaster else { return playlist }
                    return try Self.inserting(track, at: position, into: playlist, among: existing)
                })
            case .albums(let list):
                guard albumRecord == nil else { break }
                changed.content = .albums(list + [Self.makingAlbum(
                    from: draft, template: list.last, index: UInt16(clamping: newAlbumIndex),
                    persistentID: ITLibrary.newAlbumPersistentID(albums: list, tracks: updated))])
            case .opaque:
                break
            }
            return changed
        }
        return copy
    }

    // MARK: - Master playlist

    static func inserting(
        _ track: ITTrack, at position: UInt32, into playlist: ITPlaylist, among existing: [ITTrack]
    ) throws -> ITPlaylist {
        var result = playlist

        if let template = playlist.entries.last {
            var entry = template
            entry.trackID = track.uniqueID
            entry.order = (playlist.entries.map(\.order).max() ?? 0) + 1
            result.entries.append(entry)
        }

        // Criteria whose ordering we do not know by name: we check whether their table
        // is a copy of a known one. If so, they inherit its insertion point;
        // if not - we append at the end, because the permutation is a hard requirement,
        // and the order in a menu we cannot name is not.
        var indices: [UInt32: BrowseIndex] = [:]
        for mhod in playlist.mhods {
            if let index = BrowseIndex(mhod: mhod) { indices[index.criterion.rawValue] = index }
        }
        var positions: [UInt32: Int] = [:]
        var letters: [UInt32: UInt32] = [:]
        for (raw, index) in indices {
            let criterion = BrowseIndex.Criterion(rawValue: raw)
            let resolved: BrowseIndex.Criterion
            if knownCriteria.contains(criterion) {
                resolved = criterion
            } else if let twin = knownCriteria.first(where: { indices[$0.rawValue]?.entries == index.entries }) {
                resolved = twin
            } else {
                positions[raw] = index.entries.count
                letters[raw] = AlphabetJumpTable.empty
                continue
            }
            positions[raw] = insertionPosition(of: track, for: resolved, in: index.entries, among: existing)
            letters[raw] = letterCode(resolved, for: track)
        }

        result.mhods = try playlist.mhods.map { mhod in
            if var index = BrowseIndex(mhod: mhod) {
                guard let at = positions[index.criterion.rawValue] else { return mhod }
                index.entries.insert(position, at: at)
                guard index.isPermutation(of: existing.count + 1) else {
                    throw TrackInsertionError.permutationBroken(criterion: index.criterion.rawValue)
                }
                return index.mhod()
            }
            if let jump = AlphabetJumpTable(mhod: mhod) {
                guard let at = positions[jump.criterion.rawValue],
                      let letter = letters[jump.criterion.rawValue] else { return mhod }
                var perPosition: [UInt32] = []
                for entry in jump.entries {
                    perPosition += Array(repeating: entry.letter, count: Int(entry.count))
                }
                guard perPosition.count == existing.count else {
                    throw TrackInsertionError.jumpTableMismatch(
                        criterion: jump.criterion.rawValue, covered: perPosition.count, expected: existing.count)
                }
                perPosition.insert(letter, at: min(at, perPosition.count))
                return jump.rebuilt(fromRuns: perPosition.map { ($0, 1) }).mhod()
            }
            return mhod
        }
        return result
    }

    /// The place where a new track falls in an already ordered table.
    ///
    /// Not "before the first greater one" - the table on a real device is not
    /// sorted to the letter. On a test iPod the album table
    /// starts with UTOPIA, and only then comes the alphabet; with the rule
    /// "first greater one" **every** new album landed at position zero, because
    /// UTOPIA is greater than almost everything.
    ///
    /// Instead we look for the place where the new entry conflicts with the smallest
    /// number of neighbors: how many entries before it are greater than it plus how many
    /// after it are smaller. A single entry out of place shifts
    /// the result by one, not by the whole list.
    static func insertionPosition(
        of track: ITTrack, for criterion: BrowseIndex.Criterion, in entries: [UInt32], among existing: [ITTrack]
    ) -> Int {
        let key = browseKey(criterion, for: track)
        // -1 smaller, +1 greater, 0 equal - equal ones do not affect the choice.
        let comparison: [Int] = entries.map { entry in
            let slot = Int(entry)
            guard slot < existing.count else { return 0 }
            let other = browseKey(criterion, for: existing[slot])
            if other < key { return -1 }
            if key < other { return 1 }
            return 0
        }

        var lessAfter = comparison.reduce(0) { $0 + ($1 < 0 ? 1 : 0) }
        var greaterBefore = 0
        var best = lessAfter
        var bestPosition = 0
        for position in 0..<comparison.count {
            if comparison[position] < 0 { lessAfter -= 1 }
            if comparison[position] > 0 { greaterBefore += 1 }
            let conflicts = greaterBefore + lessAfter
            // On a tie we take the **later** place. A tie happens when
            // an entry out of place stands before the table: "at the very start"
            // and "after the last smaller neighbor" conflict equally, and only the
            // latter is what the user expects.
            if conflicts <= best {
                best = conflicts
                bestPosition = position + 1
            }
        }
        return bestPosition
    }

    // MARK: - Album record identity

    /// The identifier of a new `mhia` record.
    ///
    /// An album record **must not** get a track identifier. The first version
    /// took it from the same generator as the track, and the caller passed
    /// a constant generator (one identifier per added track) - so the album
    /// record got the identifier of its first track. On the device
    /// it looked like this: the album showed artwork in Cover Flow
    /// and for the first track, but not for the others.
    ///
    /// The shape comes from the device: 116 of 118 album records have the upper
    /// 32 bits equal to `0x00000002` or `0x00000102`, and the lower ones random. Tracks
    /// have full random 64 bits, so the two spaces do not mix.
    public static let albumIdentitySpace: UInt64 = 0x0000_0002 << 32

    /// Whether an identifier looks like an album record identifier.
    public static func isAlbumIdentity(_ value: UInt64) -> Bool {
        let high = UInt32(value >> 32)
        return high == 0x2 || high == 0x102
    }

    static func newAlbumPersistentID(albums: [ITAlbum], tracks: [ITTrack],
                                     random: @Sendable () -> UInt32 = { UInt32.random(in: 1...UInt32.max) }) -> UInt64 {
        let used = Set(albums.map(\.persistentID)).union(tracks.map(\.persistentID))
        // Incrementing after the first draw, not drawing in a loop: the generator
        // may be constant, and then drawing in a loop would never end.
        var candidate = albumIdentitySpace | UInt64(random())
        while used.contains(candidate) { candidate &+= 1 }
        return candidate
    }

    // MARK: - Album list

    /// A new `mhia` record. Music rewrites the number in this list anyway on the
    /// next connection; ours only has to match the track's field 0x120.
    static func makingAlbum(
        from draft: TrackDraft, template: ITAlbum?, index: UInt16, persistentID: UInt64
    ) -> ITAlbum {
        let header = template?.rawHeader ?? []
        var album = ITAlbum(
            index: index, persistentID: persistentID, title: draft.album,
            artist: draft.effectiveAlbumArtist, sortArtist: nil,
            mhods: [
                Mhod.text(type: .albumTitle, value: draft.album ?? ""),
                Mhod.text(type: .albumArtistName, value: draft.effectiveAlbumArtist),
            ],
            rawHeader: header)
        // An album without designated artwork - the artwork step will add it.
        album.artworkOwnerPersistentID = 0
        return album
    }
}
