import Foundation

/// Replaces existing artwork in place: new pixels go exactly into the
/// `.ithmb` slices that `ArtworkDB` already points to. The artwork database
/// and `iTunesDB` stay untouched - not a single offset changes, so there is
/// nothing to damage apart from the image itself. An album without artwork cannot
/// take this path (it would need new `mhii` records and space in the file).
public enum ArtworkReplacement {

    /// One slice to overwrite - the same for all tracks that iTunes
    /// deduplicated onto a shared image.
    public struct Slot: Hashable, Sendable {
        public let variant: ArtworkVariant
    }

    /// Unique slices for a set of images (an album's tracks usually share them).
    public static func slots(for images: [ArtworkImage]) -> [Slot] {
        var seen: Set<ArtworkVariant> = []
        var out: [Slot] = []
        for image in images {
            for variant in image.variants where !seen.contains(variant) {
                seen.insert(variant)
                out.append(Slot(variant: variant))
            }
        }
        return out
    }

    /// Overwrites all slices. `render` receives the variant size and must
    /// return an image of exactly that size. On an error halfway through it restores
    /// the previous bytes in the slices already overwritten and rethrows.
    /// Returns the number of slices written.
    @discardableResult
    public static func write(
        _ slots: [Slot], in paths: IPodPaths,
        render: (_ width: Int, _ height: Int) throws -> ITHMBImage
    ) throws -> Int {
        var written: [(URL, UInt64, Data)] = []   // for rollback: where, and what was there
        do {
            for slot in slots {
                let variant = slot.variant
                guard variant.hasSaneBounds else {
                    throw ITDBError.readOutOfBounds(offset: Int(variant.byteOffset), size: Int(variant.byteCount))
                }
                let image = try render(Int(variant.width), Int(variant.height))
                guard image.width == Int(variant.width), image.height == Int(variant.height) else {
                    throw ITDBError.writeRefused(.inconsistent("rendered \(image.width)x\(image.height), the variant wants \(variant.width)x\(variant.height)"))
                }
                let bytes = ITHMB.encodeRGB565(image, pixelStride: variant.pixelStride, slotSize: Int(variant.byteCount))
                let url = try variant.url(in: paths)
                let handle = try FileHandle(forUpdating: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(variant.byteOffset))
                guard let previous = try handle.read(upToCount: bytes.count), previous.count == bytes.count else {
                    throw ITDBError.readOutOfBounds(offset: Int(variant.byteOffset), size: bytes.count)
                }
                try handle.seek(toOffset: UInt64(variant.byteOffset))
                try handle.write(contentsOf: Data(bytes))
                try handle.synchronize()
                written.append((url, UInt64(variant.byteOffset), previous))
            }
        } catch {
            for (url, offset, previous) in written.reversed() {
                if let handle = try? FileHandle(forUpdating: url) {
                    try? handle.seek(toOffset: offset)
                    try? handle.write(contentsOf: previous)
                    try? handle.synchronize()
                    try? handle.close()
                }
            }
            throw error
        }
        return written.count
    }
}
