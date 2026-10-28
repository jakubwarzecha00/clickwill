import Foundation
import ITDBKit
import ClickwillModel

/// `check [--remove-orphans [--apply]]` - database consistency with files on disk;
/// `--remove-orphans` deletes files without an entry.
enum CheckCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        // Consistency computed from the same library that will be written: a file
        // added to the database after this read must not end up on the deletion list.
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let result = try IntegrityReport.build(library: onDevice.library, paths: device.paths)
        report("Consistency", [
            ("entries in the database", "\(result.trackCount)"),
            ("audio files on disk", "\(result.audioFileCount)"),
            ("entries without a file", "\(result.missingFiles.count)"),
            ("files without an entry", "\(result.orphanedFiles.count)"),
            ("entries without a path", "\(result.locationlessTracks.count)"),
            ("size mismatches", "\(result.sizeMismatches.count)"),
            ("dead references in playlists", "\(result.danglingReferences.count)"),
        ])
        if !result.missingFiles.isEmpty {
            print("\nEntries pointing to files that do not exist")
            for entry in result.missingFiles.prefix(40) {
                print("  id=\(entry.uniqueID)  \(entry.artist) - \(entry.title)")
                print("      \(entry.path)")
            }
            if result.missingFiles.count > 40 { print("  ... and \(result.missingFiles.count - 40) more") }
        }
        if !result.orphanedFiles.isEmpty {
            print("\nFiles nothing leads to")
            for path in result.orphanedFiles.prefix(20) { print("  \(path)") }
            if result.orphanedFiles.count > 20 { print("  ... and \(result.orphanedFiles.count - 20) more") }
            // --remove-orphans: files without an entry in the database, e.g. after an interrupted add.
            // Through the transaction, like every deletion: the lock (another process may
            // be copying a file it has not entered yet), the database still the one
            // read, deleting only regular files inside Music.
            if call.has("--remove-orphans") {
                var changes = ChangeSet()
                let doomed = changes.queueUnreferencedFiles(result.orphanedFiles.compactMap(device.paths.musicFile),
                                                            in: onDevice.library, paths: device.paths, files: LocalFileSystem())
                let bytes = doomed.reduce(Int64(0)) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) }
                print("\n  To delete: \(doomed.count) files, \(formatted(bytes: bytes))")
                if doomed.count < result.orphanedFiles.count {
                    print("  Staying on disk: folders, links and files outside Music.")
                }
                guard call.has("--apply") else { print("\n  That was a preview. To delete: add --apply"); return }
                guard !doomed.isEmpty else { return }
                announce(try await onDevice.write(onDevice.library, changes: changes, note: "ipodctl check --remove-orphans"))
            }
        }
        if !result.sizeMismatches.isEmpty {
            print("\nSize mismatches")
            for entry in result.sizeMismatches.prefix(20) {
                print("  id=\(entry.uniqueID)  \(entry.title): database \(entry.declared) B, disk \(entry.actual) B")
            }
        }
        if result.isClean { print("\n  No issues.") }
    }
}
