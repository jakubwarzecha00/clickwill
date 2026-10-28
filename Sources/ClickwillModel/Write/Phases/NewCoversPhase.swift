import Foundation
import ITDBKit

/// New artwork records before the database write - the database must point to a finished image:
///
/// - first artwork for albums: the image into `ArtworkDB` and the `.ithmb` files, then
///   the owner pointer in the library;
/// - an album image for more tracks: a new `mhii` per track, the same slices.
///
/// An error with one album does not stop the others.
struct NewCoversPhase: WritePhase {
    let jobs: [AlbumID: ArtworkAdditionJob]
    let sharing: [AlbumID: ArtworkSharingJob]
    /// One line per album - for `ipodctl`.
    let progress: (@Sendable (String) -> Void)?

    func run(_ library: inout ITLibrary, on device: IPodDevice, ledger: inout WriteLedger) {
        for (key, job) in jobs {
            do {
                let added = try ArtworkAddition.add(ownerPersistentID: job.ownerPersistentID, sourceByteCount: job.sourceByteCount,
                                                    trackCount: UInt32(job.trackCount), in: device.paths,
                                                    deviceFormats: device.firmwareDescription?.albumArt ?? [],
                                                    allowingUnverifiedFormats: job.allowingUnverifiedFormats) { width, height in
                    try ITHMBImage(rendering: job.image, width: width, height: height)
                }
                library = library
                    .linkingAlbumArtwork(album: job.album, ownerPersistentID: job.ownerPersistentID)
                    .markingAlbumArtwork(album: job.album, sourceByteCount: job.sourceByteCount)
                ledger.completed.covers.insert(key)
                ledger.coversWritten += 1
                ledger.artworkChanged = true
                progress?("\(job.album): artwork, mhii \(added.imageID)" + (added.createdDatabase ? ", new ArtworkDB" : ""))
            } catch {
                ledger.coverFailed(job.album, error)
            }
        }
        for (key, job) in sharing {
            do {
                let created = try ArtworkAddition.sharing(imageID: job.imageID, withTracks: job.trackIDs, in: device.paths)
                ledger.completed.sharedCovers.insert(key)
                ledger.coversWritten += 1
                ledger.artworkChanged = true
                progress?("\(job.album): image \(job.imageID) for more tracks, mhii "
                          + created.values.sorted().map(String.init).joined(separator: ", "))
            } catch {
                ledger.coverFailed(job.album, error)
            }
        }
    }
}
