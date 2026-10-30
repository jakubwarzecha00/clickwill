import Foundation

/// Repairs that run on every database write - including albums
/// the user did not touch in this session.
///
/// The order is part of the contract:
///
/// 1. The artwork marker at `mhit` 0x7E (`repairingArtworkMarkers`).
/// 2. The second copy of the track identifier at 0xA8 and the album record
///    identity (`repairingSecondaryIdentifiers`, `repairingAlbumIdentities`).
/// 3. The image owner after merging duplicates - written to `ArtworkDB`, before
///    steps 4-5, because they read `ArtworkDB` from disk. On an iPod that finds artwork
///    by the track (nano 2G), every track of an album with one picture then gets
///    its own image record (`trackImageShares`).
/// 4. The artwork source size in tracks (0x7C, 0x80) and the image pointer
///    (0x160) - from `ArtworkDB` after step 3 and after images added in this
///    transaction.
/// 5. Artwork coverage (`mhii` 0x38) - on the final library to be written.
///
/// On a model outside the confirmed ones (`albums` given) only the artwork steps that finish
/// this write's own changes run, and only for those albums: the image record per track (3),
/// the source size and pointer (4) and the coverage (5). Without them a first cover written
/// there showed nowhere on the iPod (nano 2G as an unconfirmed model). Steps 1,
/// 2 and the owner move change albums the user didn't touch, by rules from other models.
///
/// Steps 1, 2 and 4 change only the library in memory. Steps 3 and 5 write
/// `ArtworkDB`; `beforeArtworkWrite` (a backup) is called before the first such
/// write. A step that failed or could not run (for example an unreadable
/// `ArtworkDB` at step 4) does not stop the write - it goes into
/// `Report.problems`, and `ArtworkDB` stays unchanged. The report never says
/// "repaired 0" about a step that did not happen.
public enum RepairPipeline {

    public struct Report: Sendable {
        /// Records whose artwork marker at 0x7E was restored.
        public var artworkMarkers = 0
        /// Tracks (by album) whose identifier at 0xA8 was restored.
        public var secondaryIdentifiers: [String: Int] = [:]
        /// Album records that carried a track identifier.
        public var albumIdentities: [String] = []
        /// Tracks (by album) that pointed to an image of a size that does not exist.
        public var artworkSources: [String: Int] = [:]
        /// Tracks (by album) without an image record pointer at 0x160.
        public var artworkIdentifiers: [String: Int] = [:]
        /// Tracks (by album) that got their own image record (nano 2G).
        public var trackImages: [String: Int] = [:]
        /// Albums with corrected artwork coverage: "title (was → is)".
        public var coverage: [String] = []
        /// Whether any step wrote `ArtworkDB`.
        public var wroteArtworkDB = false
        /// Steps that failed or did not run - the write goes on without them.
        public var problems: [Problem] = []

        public init() {}
    }

    /// A step that did not happen.
    public struct Problem: Sendable, Equatable, CustomStringConvertible {
        public enum Step: Sendable, Equatable {
            /// 3. The image owner after merging duplicates.
            case coverOwners
            /// 3. An image record for every track (nano 2G).
            case trackImages
            /// 4. Artwork source size and image pointer (0x7C, 0x80, 0x160).
            case imageLinks
            /// 5. Artwork coverage (`mhii` 0x38).
            case coverCounts
        }
        public let step: Step
        /// Technical description - for `ipodctl` and the diagnostic report.
        public let detail: String

        public var description: String {
            switch step {
            case .coverOwners: "cover owner after merging duplicates: \(detail)"
            case .trackImages: "image records per track: \(detail)"
            case .imageLinks: "image links (0x160): \(detail)"
            case .coverCounts: "cover coverage: \(detail)"
            }
        }
    }

    /// - Parameters:
    ///   - artworkOwnerRedirects: merged duplicates, `persistentID` of the removed one ->
    ///     the one kept. The removed copy's image moves to the one kept.
    ///   - beforeArtworkWrite: called before every write of `ArtworkDB`; an error
    ///     stops that write.
    public static func run(
        _ library: ITLibrary, on device: IPodDevice,
        artworkOwnerRedirects: [UInt64: UInt64] = [:],
        albums scope: Set<String>? = nil,
        beforeArtworkWrite: () throws -> Void
    ) -> (library: ITLibrary, report: Report) {
        var library = library
        var report = Report()
        let manager = FileManager.default
        let artworkDB = device.paths.artworkDB
        func inScope(_ album: String) -> Bool { scope?.contains(album) ?? true }
        func scoped<Value>(_ byAlbum: [String: Value]) -> [String: Value] { byAlbum.filter { inScope($0.key) } }

        if scope == nil {
            // 1. Records added by earlier versions had zero at 0x7E
            // and did not show artwork for the song playing.
            let markers = library.repairingArtworkMarkers()
            library = markers.library
            report.artworkMarkers = markers.repaired

            // 2. Both defects look the same - artwork in Cover Flow is there,
            // for the song it is not - but they have different causes.
            let secondary = library.repairingSecondaryIdentifiers()
            library = secondary.library
            report.secondaryIdentifiers = secondary.repaired
            let identities = library.repairingAlbumIdentities()
            library = identities.library
            report.albumIdentities = identities.repaired
        }

        // 3. Cover Flow finds artwork through the owner. If the database write
        // failed, the old database has both tracks, so moving the owner breaks nothing.
        if scope == nil, !artworkOwnerRedirects.isEmpty, manager.fileExists(atPath: artworkDB.path) {
            do {
                let outcome = try ArtworkDBEditor.settingOwners(artworkOwnerRedirects, in: Data(contentsOf: artworkDB))
                if outcome.changed > 0 {
                    try beforeArtworkWrite()
                    try outcome.data.write(to: artworkDB, options: .atomic)
                    report.wroteArtworkDB = true
                }
            } catch {
                report.problems.append(Problem(step: .coverOwners, detail: "\(error)"))
            }
        }

        // 3. The nano 2G looks artwork up by the track, so every track of an album
        // needs its own record - the same slices, no new pixels. New artwork and new
        // albums get one record from the steps before; this gives the rest of the album theirs.
        if device.findsArtworkByTrack, manager.fileExists(atPath: artworkDB.path) {
            do {
                let shares = try ArtworkDBParser.parse(Data(contentsOf: artworkDB)).trackImageShares(in: library)
                    .filter { inScope($0.album) }
                if !shares.isEmpty { try beforeArtworkWrite() }
                for share in shares {
                    let created = try ArtworkAddition.sharing(imageID: share.imageID, withTracks: share.tracks, in: device.paths)
                    guard !created.isEmpty else { continue }
                    report.trackImages[share.album] = created.count
                    report.wroteArtworkDB = true
                }
            } catch {
                report.problems.append(Problem(step: .trackImages, detail: "\(error)"))
            }
        }

        // 4. A track pointing to an image of a size that does not exist in the database, or
        // without a pointer at 0x160, will not show artwork during playback, even though
        // the album shows it in Cover Flow.
        // Without `ArtworkDB` there is nothing to point to; an unreadable one is different -
        // then the step did not happen and the report must say so.
        do {
            if let artwork = try device.readArtwork() {
                let sources = library.repairingArtworkSources(imageSourcesByAlbum: scoped(artwork.imageSourcesByAlbum(in: library)))
                library = sources.library
                report.artworkSources = sources.repaired
                let identifiers = library.repairingArtworkIdentifiers(
                    imageIdentifiersByAlbum: scoped(artwork.imageIdentifiersByAlbum(in: library)),
                    existingIdentifiers: artwork.imageIdentifiers)
                library = identifiers.library
                report.artworkIdentifiers = identifiers.repaired
            }
        } catch {
            report.problems.append(Problem(step: .imageLinks, detail: "ArtworkDB unreadable: \(error)"))
        }

        // 5. `mhii` 0x38 says how many tracks of the album the image applies to, and it
        // decides whether the iPod shows the artwork. Adding or removing a track
        // throws that number off, so we settle it on the final library.
        if manager.fileExists(atPath: artworkDB.path) {
            do {
                let outcome = try ArtworkCoverage.repairing(Data(contentsOf: artworkDB), library: library, paths: device.paths,
                                                            albums: scope)
                if !outcome.repaired.isEmpty {
                    try beforeArtworkWrite()
                    try outcome.data.write(to: artworkDB, options: .atomic)
                    report.wroteArtworkDB = true
                    report.coverage = outcome.repaired.map { "\($0.title) (\($0.declared) → \($0.trackCount))" }
                }
            } catch {
                report.problems.append(Problem(step: .coverCounts, detail: "\(error)"))
            }
        }
        return (library, report)
    }
}
