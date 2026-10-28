import Foundation
import Observation
import CoreGraphics
import ITDBKit

/// Album artwork in the app's memory, by the identifier of the hook track
/// (`AlbumCard.artworkTrackID`).
///
/// A view reads the artwork synchronously (`image(for:)`) and asks once for it to be
/// decoded (`ensure(_:)`, usually in `.task(id:)`). Decoding from `.ithmb`
/// runs in the background (`ArtworkCache`), and the finished image appears here and the view
/// refreshes.
///
/// After reloading the library from the same source (Discard All) the images
/// are thrown away, because they may be a preview of a discarded change, and the artwork
/// the views have already asked for decodes again by itself. A view will not ask a second time:
/// the track identifier does not change, so `.task(id:)` does not run.
@MainActor
@Observable
public final class CoverImages {
    /// Images ready to show, including previews of artwork waiting to be written.
    private var images: [UInt64: CGImage] = [:]
    /// Identifiers the views have asked for since the last load.
    @ObservationIgnored private var requested: Set<UInt64> = []
    /// Grows with every load and clearing; an image decoded for
    /// the old library must not reach the new one.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let cache = ArtworkCache()
    /// A reload in progress: a view's request during it waits for the new index.
    @ObservationIgnored private var reloading: Task<Void, Never>?
    /// The last work handed to `cache` (`reown`, a reload). Each new one
    /// waits for the previous one, so `cache` sees them in the order requested - otherwise
    /// a late `reown` would move images in a fresh index.
    @ObservationIgnored private var cacheWork: Task<Void, Never>?
    /// Decoding after a reload - tests wait for it to finish.
    @ObservationIgnored private(set) var refresh: Task<Void, Never>?

    public init() {}

    public func image(for trackID: UInt64?) -> CGImage? {
        guard let trackID else { return nil }
        return images[trackID]
    }

    /// Decodes artwork if it is not there yet. Safe to call repeatedly.
    public func ensure(_ trackID: UInt64?) async {
        guard let trackID, images[trackID] == nil else { return }
        requested.insert(trackID)
        await reloading?.value
        let started = generation
        if let image = await cache.image(forTrack: trackID), generation == started {
            images[trackID] = image
        }
    }

    /// A preview of artwork that is not on the iPod yet (new album artwork,
    /// an album waiting in the add queue).
    func show(_ image: CGImage, for trackIDs: some Sequence<UInt64>) {
        for id in trackIDs { images[id] = image }
    }

    /// Images moved to another track (merged duplicates) - the artwork stays
    /// in place even before the write.
    func reown(_ owners: [UInt64: UInt64]) {
        for (old, new) in owners {
            if let image = images[old] { images[new] = image }
            if requested.contains(old) { requested.insert(new) }
        }
        let previous = cacheWork
        cacheWork = Task { [cache] in
            await previous?.value
            await cache.reown(owners)
        }
    }

    /// A new library. `keepRequested`: the same source - artwork the views
    /// asked for decodes again without a new request.
    func reload(paths: IPodPaths?, artwork: ArtworkLibrary?, keepRequested: Bool) async {
        let wanted = keepRequested ? requested : []
        generation += 1
        let current = generation
        images = [:]
        requested = wanted
        refresh?.cancel()
        // In turn with other work on `cache`, including the previous reload.
        let previous = cacheWork
        let reset = Task { [cache] in
            await previous?.value
            await cache.reset(paths: paths, artwork: artwork)
        }
        cacheWork = reset
        reloading = reset
        await reset.value
        // A newer load or a disconnect came in the meantime - they decide.
        guard generation == current else { return }
        reloading = nil
        refresh = Task { [weak self] in
            for id in wanted {
                guard let self, !Task.isCancelled, self.generation == current else { return }
                if self.images[id] == nil, let image = await self.cache.image(forTrack: id), self.generation == current {
                    self.images[id] = image
                }
            }
        }
    }

    /// The library is gone (the iPod was disconnected).
    func clear() {
        generation += 1
        images = [:]
        requested = []
        refresh?.cancel()
        refresh = nil
    }
}
