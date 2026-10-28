import Foundation
import CoreGraphics
import ITDBKit

/// Artwork decoded from `.ithmb` on demand, kept in memory.
///
/// An actor, because RGB565 decoding runs off the main thread, and Cover Flow asks
/// for a dozen covers at once on the first scroll.
actor ArtworkCache {
    private var paths: IPodPaths?
    private var byTrack: [UInt64: ArtworkImage] = [:]
    private var decoded: [UInt64: CGImage] = [:]
    private var failed: Set<UInt64> = []

    init() {}

    func reset(paths: IPodPaths?, artwork: ArtworkLibrary?) {
        self.paths = paths
        self.byTrack = artwork?.indexedByTrack() ?? [:]
        decoded = [:]
        failed = []
    }

    /// Images moved to another track (merged duplicates). The decoded image
    /// goes with it, so the artwork does not have to be decoded a second time.
    func reown(_ owners: [UInt64: UInt64]) {
        for (old, new) in owners {
            guard let entry = byTrack.removeValue(forKey: old) else { continue }
            byTrack[new] = entry
            failed.remove(new)
            if let image = decoded.removeValue(forKey: old) { decoded[new] = image }
        }
    }

    /// The largest artwork variant for a track. `nil` when there is none or it cannot be decoded.
    func image(forTrack id: UInt64) -> CGImage? {
        if let cached = decoded[id] { return cached }
        guard !failed.contains(id), let paths, let entry = byTrack[id], let variant = entry.largest else {
            failed.insert(id)
            return nil
        }
        guard let image = try? ITHMB.read(variant, in: paths).makeCGImage() else {
            failed.insert(id)
            return nil
        }
        decoded[id] = image
        return image
    }
}
