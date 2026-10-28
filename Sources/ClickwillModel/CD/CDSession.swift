import Foundation
import ImageIO
import Observation

/// One disc: the album draft, the MusicBrainz lookup, ripping to the Mac.
///
/// The ripped files go to whoever started the rip (`rip(done:)`) - the app
/// hands them to the add sheet, so the disc goes through the same duplicate
/// check as any other album.
@MainActor @Observable
public final class CDSession {
    public let disc: AudioCD
    public var draft: CDDraft
    public private(set) var releases: [CDRelease] = []
    public private(set) var lookup: LookupState = .idle
    public var format: CDRipper.Format {
        didSet { services.formatMemory.save(format) }
    }
    /// The song being ripped (index among the checked ones) and the progress in it.
    public private(set) var ripping: RipProgress?
    /// Numbers of the songs already ripped.
    public private(set) var ripped: Set<Int> = []
    public private(set) var outcome: CDRipper.Outcome?
    /// Stable song identifiers for previewing (the player counts by UUID).
    public let previewIDs: [Int: UUID]
    private var ripTask: Task<Void, Never>?
    @ObservationIgnored private let services: CDServices

    public enum LookupState: Equatable { case idle, looking, found, notFound, failed(LookupFailure) }

    public enum LookupFailure: Equatable {
        /// No connection, or the server did not respond.
        case unreachable
        /// The server responded, but the response cannot be used.
        case badAnswer(MusicBrainz.LookupError)
    }

    public struct RipProgress: Equatable {
        public let index: Int
        public let fraction: Double
    }

    /// The result of pasting a track list.
    public enum PasteResult: Equatable {
        case filled
        /// The text has not a single title.
        case noTrackList
        /// The number of titles differs from the number of songs - the draft is unchanged.
        case countMismatch(lines: Int, songs: Int)
    }

    public init(disc: AudioCD, services: CDServices) {
        self.disc = disc
        self.services = services
        draft = CDDraft(disc: disc)
        format = services.formatMemory.load() ?? .appleLossless
        previewIDs = Dictionary(uniqueKeysWithValues: disc.tracks.map { ($0.number, UUID()) })
    }

    public var isRipping: Bool { ripTask != nil }
    /// Names have not been looked up yet (or the lookup failed) - then that is the next step.
    public var needsLookUp: Bool {
        switch lookup {
        case .idle, .failed: return true
        case .looking, .found, .notFound: return false
        }
    }
    public var title: String { draft.album.isEmpty ? "Audio CD" : draft.album }
    public var selectedRelease: CDRelease? { releases.first { $0.id == draft.releaseID } }

    /// The length of the checked tracks.
    public var includedMilliseconds: UInt64 { draft.includedSongs.reduce(0) { $0 + UInt64($1.durationMilliseconds) } }

    /// "Look Up Online": releases matching the disc, then the artwork of the first one.
    public func lookUp() async {
        guard lookup != .looking else { return }
        lookup = .looking
        do {
            releases = try await services.lookup.releases(disc)
            guard let first = releases.first else { lookup = .notFound; return }
            lookup = .found
            await choose(first)
        } catch let error as MusicBrainz.LookupError {
            lookup = .failed(.badAnswer(error))
        } catch {
            lookup = .failed(.unreachable)
        }
    }

    /// Choosing a release (when there are several). Overwrites the names; the artwork arrives a moment later.
    public func choose(_ release: CDRelease) async {
        draft.apply(release)
        let cover = try? await services.lookup.frontCover(release)
        // The user may have chosen another release or their own artwork in the meantime.
        if draft.releaseID == release.id, draft.cover == nil { draft.cover = cover ?? nil }
    }

    /// The state after a lookup with a ready result, without waiting for the server.
    public func showFound(_ releases: [CDRelease], cover: Data?) {
        guard let first = releases.first else { return }
        self.releases = releases
        lookup = .found
        draft.apply(first)
        draft.cover = cover
    }

    /// A track list pasted from the clipboard, one title per line.
    public func pasteTrackList(_ text: String) -> PasteResult {
        let found = draft.applyPasted(text)
        if found == draft.songs.count { return .filled }
        if found == 0 { return .noTrackList }
        return .countMismatch(lines: found, songs: draft.songs.count)
    }

    /// Artwork from a file. A file that cannot be read as an image changes nothing.
    @discardableResult
    public func setCover(from url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), Self.isImage(data) else { return false }
        draft.cover = data
        return true
    }

    /// The same check as when changing an album's artwork (`LibraryModel.loadImage`):
    /// an image that can later be written to the iPod.
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) != nil
    }

    /// Rips the checked songs to the Mac; `done` receives the finished files.
    public func rip(done: @escaping @MainActor ([URL]) -> Void) {
        guard ripTask == nil, draft.missing == nil else { return }
        let draft = draft
        let format = format
        let destination = services.ripping
        ripped = []
        outcome = nil
        ripping = RipProgress(index: 0, fraction: 0)
        let included = draft.includedSongs.map(\.number)
        ripTask = Task {
            let outcome = await CDRipper.rip(draft, as: format, root: destination.root, pace: destination.pace) { index, fraction in
                Task { @MainActor in
                    guard self.ripTask != nil else { return }
                    self.ripping = RipProgress(index: index, fraction: fraction)
                    if fraction >= 1, included.indices.contains(index) { self.ripped.insert(included[index]) }
                }
            }
            self.outcome = outcome
            self.ripping = nil
            self.ripTask = nil
            if !Task.isCancelled, !outcome.files.isEmpty { done(outcome.files) }
        }
    }

    public func cancelRip() {
        ripTask?.cancel()
        ripTask = nil
        ripping = nil
    }

    public func eject() {
        cancelRip()
        let volume = disc.volume
        let eject = services.drive.eject
        Task.detached { eject(volume) }
    }
}
