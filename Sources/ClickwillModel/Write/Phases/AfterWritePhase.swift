import Foundation
import ITDBKit

/// Everything that may be done only after a successful database write, because the new database no longer
/// points to it: deleting the files of removed tracks and old files
/// after a conversion or replacement, replacing artwork in place of existing slices.
struct AfterWritePhase {
    /// Files of removed tracks, with the plan for copies on the Mac.
    let filesToDelete: [URL]
    let archiveBeforeDelete: [URL: ArchivePlan]
    let replacements: [AlbumID: ArtworkReplacementJob]
    let files: any FileSystem

    /// Old files are taken from the ledger (`oldFiles`). A file that could not be
    /// deleted for a temporary reason waits for the next write; a file the
    /// rule rejects (a folder, a link, something outside `Music`) goes only to
    /// the report - on the next write it would be rejected the same way.
    func run(on device: IPodDevice, ledger: inout WriteLedger) {
        let music = device.paths.musicDirectory
        // We delete only on the same volume the database went to.
        let mounted = (try? device.volume.ensureStillMounted()) != nil
        if !mounted { retry(filesToDelete + ledger.oldFiles, in: &ledger) }
        // The same protection as when removing: the old path comes from the database.
        for url in mounted ? ledger.oldFiles : [] where files.fileExists(at: url) {
            guard DeviceFiles.isDeletableAudioFile(url, under: music, files: files) else {
                ledger.oldFileProblems.append(WriteProblem(url.lastPathComponent, .keptByRule))
                continue
            }
            do { try files.removeItem(at: url) } catch { ledger.oldFileProblems.append(WriteProblem(url.lastPathComponent, .notDeleted(error))) }
        }
        for url in mounted ? filesToDelete : [] {
            guard files.fileExists(at: url) else { continue }
            // Checked when added to the queue, but the path may have changed its
            // target since then (a link) - once more before deleting.
            guard DeviceFiles.isDeletableAudioFile(url, under: music, files: files) else {
                ledger.keptFiles.append(url)
                continue
            }
            // The copy goes first. When it fails, the file is not touched - better
            // to leave it on the iPod than to delete it without the promised copy.
            if let plan = archiveBeforeDelete[url] {
                do { _ = try OriginalArchive.store(url, in: plan.directory, as: plan.fileName) }
                catch { retry([url], in: &ledger); continue }
            }
            do { try files.removeItem(at: url); ledger.deletedFiles += 1 } catch { retry([url], in: &ledger) }
        }
        // Artwork in place of existing slices. An error with one album does not
        // block the rest - the unwritten ones stay in the queue.
        for (key, job) in replacements {
            do {
                try ArtworkReplacement.write(job.slots, in: device.paths) { width, height in
                    try ITHMBImage(rendering: job.image, width: width, height: height)
                }
                ledger.completed.covers.insert(key)
                ledger.coversWritten += 1
                ledger.artworkChanged = true
            } catch {
                ledger.coverFailed(job.album, error)
            }
        }
    }

    /// Not deleted now, to retry on the next write.
    private func retry(_ urls: [URL], in ledger: inout WriteLedger) {
        ledger.completed.deletionsToRetry += urls
    }
}
