import Foundation
import CryptoKit

/// The result of writing the database to the device.
public struct DatabaseWriteResult: Sendable {
    public let snapshot: Snapshot
    public let byteCount: Int
    public let signature: String
    /// Digest of the written database (`IPodDevice.digest(of:)`) - from the bytes that
    /// reading back from the medium confirmed. The reference point for the next write.
    public let digest: String
    /// `true` when the written bytes are identical to what was already on the iPod.
    public let identicalToPrevious: Bool
    /// How many tracks had plays merged in from `Play Counts` in this transaction.
    public let mergedPlayCounts: Int
    public let preflight: WritePreflight
    /// The library exactly in the form that went to disk - with the merged plays.
    /// The caller must adopt it; keeping the version from before the merge would roll the
    /// counters back on the next write.
    public let writtenLibrary: ITLibrary
    /// `false` when the database was replaced, but the `Play Counts` file could not be deleted.
    /// Writing again would count the same plays a second time.
    public let playCountsRemoved: Bool
}


extension IPodDevice {

    /// Writes the database to the device. Every step is a gate - an error at any
    /// of them stops the operation before anything touches the iPod.
    ///
    /// 0. preflight: volume available, Music closed, pending plays merged,
    /// 1. a fresh backup,
    /// 2. assembling the database and signing it with the device key,
    /// 3. parsing the result again and comparing it with the model - before anything is written,
    /// 4. writing to a temporary file on the iPod volume and forcing a flush to the medium,
    /// 5. reading that file back from disk and comparing byte for byte,
    /// 6. only now the rename.
    @discardableResult
    public func writeDatabase(
        _ library: ITLibrary,
        using store: SnapshotStore,
        reason: SnapshotReason = .beforeWrite(changes: nil),
        note: String? = nil,
        options: WriteOptions = WriteOptions()
    ) throws -> DatabaseWriteResult {
        guard supportsWriting else {
            throw ITDBError.writeRefused(.readOnly(readOnlyReason))
        }
        try volume.ensureStillMounted()

        let preflight = preflightForWriting(isMusicRunning: options.isMusicRunning)
        if let issue = preflight.refusal(allowingMusic: options.allowWhileMusicRunning) {
            throw ITDBError.writeRefused(.preflight(issue))
        }

        let previous = try readDatabase()
        try Self.ensureUnchanged(previous, since: options.expectedSourceDigest)
        try ensureUnderstood(previous)
        let snapshot = try store.capture(from: self, reason: reason, note: note ?? "before database write")

        // Plays correspond to records by position in the database that lies on disk -
        // so positions are mapped to identifiers through it, and the merge then goes by
        // identifiers onto the outgoing database. Tracks removed by the caller
        // simply do not get their pending statistics.
        var outgoing = library
        var merged = 0
        if let counts = try readPlayCounts() {
            // On an unconfirmed model only the measured layout is merged. Reading entries
            // of another length on a guess could hand plays to the wrong songs.
            if writesOutsideConfirmedModels && writePolicy == .experimental && !counts.hasMeasuredLayout {
                throw ITDBError.writeRefused(.unmergedPlayCounts(
                    "Play Counts layout not measured on an unconfirmed model (\(counts.layoutSummary))"))
            }
            let onDisk = try ITunesDBParser.parse(previous)
            // The file corresponds to records by position - any length mismatch means
            // there is no telling which tracks the statistics belong to.
            guard counts.entries.count == onDisk.tracks.count else {
                throw ITDBError.writeRefused(.unmergedPlayCounts(
                    "Play Counts has \(counts.entries.count) entries, the library on the iPod \(onDisk.tracks.count) songs"))
            }
            guard options.mergePendingPlayCounts else {
                throw ITDBError.writeRefused(.unmergedPlayCounts("merging plays is turned off"))
            }
            // An increment, not the value from disk: the caller may already have changed
            // the count in the library (merging duplicates adds up the plays of both copies).
            let merge = PlayCounts.applying(counts, recordedFor: onDisk.tracks, to: library,
                                            redirects: options.playCountRedirects)
            outgoing = merge.library
            merged = merge.changed
        }

        try Self.verifyConsistency(of: outgoing)
        let signer = self.signer
        let payload = try signer.sign(ITunesDBWriter.serialize(outgoing))
        try Self.verifyStructure(of: payload, matches: outgoing, signer: signer)

        let destination = paths.iTunesDB
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".iTunesDB.pending")

        let manager = FileManager.default
        if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        try payload.write(to: staging, options: .atomic)
        try Self.flushToDisk(staging)

        // Read from disk, not from memory - the point is whether the medium really took it.
        let readBack = try Data(contentsOf: staging)
        guard readBack == payload else {
            try? manager.removeItem(at: staging)
            throw ITDBError.writeVerificationFailed(
                reason: "the file read back from the iPod differs from what was written"
            )
        }

        // The last moment before the rename: the same volume as when it was opened.
        do { try volume.ensureStillMounted() } catch { try? manager.removeItem(at: staging); throw error }
        _ = try manager.replaceItemAt(destination, withItemAt: staging)

        // Only after a successful rename. The file is an increment since the last merge;
        // from now on it is in the database, and Music will find nothing to merge.
        // A failure here is not a write error - the database is already in place - only a
        // partial state that the caller must report, not retry.
        var playCountsRemoved = true
        if manager.fileExists(atPath: paths.playCounts.path) {
            do { try manager.removeItem(at: paths.playCounts) } catch { playCountsRemoved = false }
        }

        return DatabaseWriteResult(
            snapshot: snapshot,
            byteCount: payload.count,
            signature: try signer.storedSignatureHex(in: payload),
            digest: Self.digest(of: payload),
            identicalToPrevious: payload == previous,
            mergedPlayCounts: merged,
            preflight: preflight,
            writtenLibrary: outgoing,
            playCountsRemoved: playCountsRemoved
        )
    }

    /// An experimental device writes only while we understand its database: the bytes
    /// on it must rebuild exactly before every write, not only during diagnostics.
    func ensureUnderstood(_ database: Data) throws {
        guard writesOutsideConfirmedModels, writePolicy == .experimental else { return }
        let trip = try RoundTrip.measure(database, fireWireID: fireWireID?.bytes)
        guard trip.isIdentical else { throw ITDBError.writeRefused(.databaseNotReproduced(trip.summary)) }
    }

    /// Rejects the write when the database on the device is not the one the edit
    /// started from (`digest(of:)` from the moment of loading). `nil` - no check.
    /// The write transaction calls this before the first file, the writer - before the database.
    public func ensureDatabaseUnchanged(since digest: String?) throws {
        guard digest != nil else { return }
        try Self.ensureUnchanged(try readDatabase(), since: digest)
    }

    static func ensureUnchanged(_ database: Data, since digest: String?) throws {
        guard let digest, digest != Self.digest(of: database) else { return }
        throw ITDBError.writeRefused(.databaseChanged)
    }

    /// Database digest - to detect that someone (Music) replaced it between loading and writing.
    public static func digest(of data: Data) -> String {
        var hash = Insecure.SHA1()
        hash.update(data: data)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Logical consistency that the signature alone does not prove: every browse table
    /// is a permutation of all tracks, no playlist points to a track
    /// that does not exist, and both copies of the master playlist carry the same tables.
    static func verifyConsistency(of library: ITLibrary) throws {
        let count = library.tracks.count
        let ids = Set(library.tracks.map(\.uniqueID))
        var masterTables: [[UInt8]] = []

        for section in library.sections {
            guard case .playlists(let playlists) = section.content else { continue }
            for playlist in playlists {
                if let dangling = playlist.entries.first(where: { !ids.contains($0.trackID) }) {
                    throw ITDBError.writeVerificationFailed(
                        reason: "playlist '\(playlist.name ?? "?")' points to a missing song \(dangling.trackID)")
                }
                guard playlist.isMaster else { continue }
                var tables: [UInt8] = []
                for mhod in playlist.mhods {
                    if let index = BrowseIndex(mhod: mhod) {
                        guard index.isPermutation(of: count) else {
                            throw ITDBError.writeVerificationFailed(
                                reason: "table '\(index.criterion.label)' isn't a permutation of \(count) songs")
                        }
                        tables += mhod.rawBody
                    }
                    if let jump = AlphabetJumpTable(mhod: mhod) {
                        let covered = jump.entries.reduce(0) { $0 + Int($1.count) }
                        guard covered == count || jump.entries.isEmpty else {
                            throw ITDBError.writeVerificationFailed(
                                reason: "jump table '\(jump.criterion.label)' covers \(covered) entries instead of \(count)")
                        }
                        tables += mhod.rawBody
                    }
                }
                masterTables.append(tables)
            }
        }
        if let first = masterTables.first, masterTables.contains(where: { $0 != first }) {
            throw ITDBError.writeVerificationFailed(reason: "the copies of the master playlist have different browsing tables")
        }
    }

    /// Checks that the assembled bytes parse back into the same thing,
    /// and that the signature is valid. Without this we would be writing blind.
    private static func verifyStructure(
        of payload: Data, matches library: ITLibrary, signer: DatabaseSigner
    ) throws {
        let reparsed: ITLibrary
        do {
            reparsed = try ITunesDBParser.parse(payload)
        } catch {
            throw ITDBError.writeVerificationFailed(reason: "the built library can't be parsed: \(error)")
        }

        guard reparsed.tracks.count == library.tracks.count else {
            throw ITDBError.writeVerificationFailed(
                reason: "the built library has \(reparsed.tracks.count) songs instead of \(library.tracks.count)"
            )
        }
        guard reparsed.sections.count == library.sections.count else {
            throw ITDBError.writeVerificationFailed(
                reason: "the built library has \(reparsed.sections.count) sections instead of \(library.sections.count)"
            )
        }
        let expectedIDs = library.tracks.map(\.uniqueID)
        guard reparsed.tracks.map(\.uniqueID) == expectedIDs else {
            throw ITDBError.writeVerificationFailed(reason: "song identifiers differ after building")
        }
        guard try signer.verify(payload) else {
            throw ITDBError.writeVerificationFailed(
                reason: "the signature (\(signer.format.name)) doesn't match the contents")
        }
    }

    /// `F_FULLFSYNC` forces a flush to the medium itself, not just to the system buffer.
    /// On the iPod's spinning disk that is a real difference.
    private static func flushToDisk(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        if fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 {
            throw ITDBError.writeVerificationFailed(
                reason: "couldn't force the data onto the disk (errno \(errno))"
            )
        }
    }
}
