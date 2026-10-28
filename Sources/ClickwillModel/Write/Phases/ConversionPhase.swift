import Foundation
import ITDBKit

/// Transcoding tracks the iPod will not play.
///
/// At no moment is there a state without a copy: the original to the archive (when
/// a folder was given), the conversion, the new file next to the old one, the library points to
/// the new file. The old file goes away only after a successful database write (`oldFiles`).
struct ConversionPhase: WritePhase {
    let jobs: [UInt32: ConversionJob]
    let capabilities: IPodCapabilities
    /// One line per file - for `ipodctl`.
    let progress: (@Sendable (String) -> Void)?

    func run(_ library: inout ITLibrary, on device: IPodDevice, ledger: inout WriteLedger) async {
        for (id, job) in jobs {
            progress?("\(job.title): \(job.fromLabel) -> \(job.target.label)")
            do {
                let track = library.tracks.first { $0.uniqueID == id }
                if let directory = job.archiveDirectory {
                    let name = OriginalArchive.fileName(artist: track?.artist, album: track?.album,
                                                        trackNumber: track?.trackNumber ?? 0, title: track?.title,
                                                        fileExtension: job.source.pathExtension)
                    _ = try OriginalArchive.store(job.source, in: directory, as: name)
                }
                let temporary = try await AudioFiles.convert(job.source, to: job.target)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let after = await AudioFiles.stream(at: temporary),
                      AudioCompatibility.verdict(for: after, on: capabilities).isSupported else {
                    ledger.conversionProblems.append(WriteProblem(job.title, .stillNotPlayable))
                    continue
                }
                let placement = try FileReplacement.place(temporary, in: device.paths,
                                                          preferredDirectory: FileReplacement.directory(of: track?.relativePath))
                ledger.placed.append(placement.url)
                library = library.mappingTracks { track in
                    guard track.uniqueID == id else { return track }
                    return track.replacingFile(relativePath: placement.relativePath, sizeBytes: placement.sizeBytes,
                                               bitRate: UInt32(after.bitRate / 1000), sampleRate: UInt32(after.sampleRate),
                                               kind: job.target.kindForDevice)
                }
                ledger.oldFiles.append(job.source)
                ledger.completed.conversions.insert(id)
                ledger.convertedFiles += 1
            } catch {
                ledger.conversionProblems.append(WriteProblem(job.title, .error(error)))
            }
        }
    }
}
