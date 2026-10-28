import Foundation
import ITDBKit

/// Files chosen for existing entries: restoring a missing one or
/// replacing the current one. The record stays the same (identifier, plays,
/// artwork) - the path and the file parameters change.
///
/// The file reaches the iPod before the database, because an entry pointing to an empty place is
/// worse than a file nobody sees. A replaced old file goes away
/// only after a successful database write (`oldFiles`).
struct FileImportPhase: WritePhase {
    let jobs: [UInt32: PendingFileImport]
    let capabilities: IPodCapabilities

    func run(_ library: inout ITLibrary, on device: IPodDevice, ledger: inout WriteLedger) async {
        for (id, job) in jobs {
            do {
                var source = job.source
                var temporary: URL?
                var bitRate = job.bitRate
                var sampleRate = job.sampleRate
                if let target = job.target {
                    let converted = try await AudioFiles.convert(job.source, to: target)
                    temporary = converted
                    source = converted
                    guard let after = await AudioFiles.stream(at: converted),
                          AudioCompatibility.verdict(for: after, on: capabilities).isSupported else {
                        try? FileManager.default.removeItem(at: converted)
                        ledger.restoreProblems.append(WriteProblem(job.title, .stillNotPlayable))
                        continue
                    }
                    bitRate = UInt32(clamping: after.bitRate / 1000)
                    sampleRate = UInt32(clamping: after.sampleRate)
                }
                // The new file next to the old one, in the same folder, if possible.
                let placement = try FileReplacement.place(
                    source, in: device.paths,
                    preferredDirectory: FileReplacement.directory(of: library.tracks.first { $0.uniqueID == id }?.relativePath))
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                ledger.placed.append(placement.url)
                library = library.mappingTracks { track in
                    guard track.uniqueID == id else { return track }
                    return track.replacingFile(
                        relativePath: placement.relativePath, sizeBytes: placement.sizeBytes,
                        durationMilliseconds: job.durationMilliseconds > 0 ? job.durationMilliseconds : nil,
                        bitRate: bitRate, sampleRate: sampleRate, kind: job.kind)
                }
                if let replaced = job.replacing { ledger.oldFiles.append(replaced) }
                ledger.completed.fileImports.insert(id)
                ledger.restoredFiles += 1
            } catch {
                ledger.restoreProblems.append(WriteProblem(job.title, .error(error)))
            }
        }
    }
}
