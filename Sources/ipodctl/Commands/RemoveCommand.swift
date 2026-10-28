import Foundation
import ITDBKit
import ClickwillModel

/// `remove (--dead | --id N,N | --orphan-albums) [--apply]` - removing tracks
/// from the database with remapping of the tables. Files disappear from the iPod only after
/// the database write, and only those that may be deleted - the same rule as in the app
/// window (`ChangeSet.queueFiles`).
enum RemoveCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library

        // Album records without tracks - they remain after the last song is removed.
        if call.has("--orphan-albums") {
            let orphans = library.orphanedAlbumRecords()
            report("Orphaned album records", [("found", "\(orphans.count)")])
            for album in orphans { print("  \(album.title ?? "?")  /  \(album.artist ?? "?")  [mhia \(album.index)]") }
            guard !orphans.isEmpty else { return }
            guard call.has("--apply") else { print("\n  That was a preview. To write: add --apply"); return }
            announce(try await onDevice.write(library.removingOrphanedAlbumRecords(),
                                          note: "ipodctl remove --orphan-albums (\(orphans.count))"))
            return
        }
        let paths = device.paths

        var wanted: Set<UInt32> = []
        if call.has("--dead") {
            // From the same library that will be written.
            let integrity = try IntegrityReport.build(library: library, paths: paths)
            wanted = Set(integrity.missingFiles.map(\.uniqueID))
            guard !wanted.isEmpty else {
                print("There are no dead entries - every track in the database has its file.")
                return
            }
        } else if let list = call.value(for: "--id") {
            wanted = Set(list.split(separator: ",").compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) })
            guard !wanted.isEmpty else { throw CommandError("--id expects comma-separated identifiers") }
        } else {
            throw CommandError("give --dead (all entries without a file) or --id N,N,N")
        }

        let manager = FileManager.default
        let plan = try library.planRemoval(uniqueIDs: wanted) { relative in
            paths.musicFile(relative).map { manager.fileExists(atPath: $0.path) } ?? false
        }
        let updated = try library.removingTracks(uniqueIDs: wanted)
        var changes = ChangeSet()
        let doomed = changes.queueFiles(of: library.tracks.filter { wanted.contains($0.uniqueID) }, keeping: updated,
                                        paths: paths, files: LocalFileSystem(), keepCopiesIn: nil)

        let byAlbum = Dictionary(grouping: plan.items, by: { $0.album.isEmpty ? "(no album)" : $0.album })
        report("Removing tracks", [
            ("tracks", "\(plan.items.count) of \(library.tracks.count)"),
            ("with a file on disk", "\(plan.filesToDelete.count)"),
            ("files to delete", "\(doomed.count)"),
            ("entries in playlists", "\(plan.playlistEntries)"),
            ("tables to remap", "\(plan.browseTables)"),
        ])
        if doomed.count < plan.filesToDelete.count {
            print("  Staying on disk: files another track points to, folders and links.")
        }
        print("")
        for (album, items) in byAlbum.sorted(by: { $0.value.count > $1.value.count }) {
            let total = library.tracks.filter { ($0.album ?? "") == items[0].album }.count
            print("  \(album)  -  \(items.count) of \(total)")
            for item in items.prefix(4) { print("      \(item.title)") }
            if items.count > 4 { print("      ... and \(items.count - 4) more") }
        }

        guard call.has("--apply") else {
            print("\n  That was a preview. To write: add --apply")
            return
        }

        // Gate: after the removal every table must still be a full permutation,
        // and no playlist may point to a track that does not exist.
        let remaining = updated.tracks.count
        guard remaining == library.tracks.count - plan.items.count else {
            throw CommandError("after the removal \(remaining) tracks remained instead of \(library.tracks.count - plan.items.count)")
        }
        if let master = updated.masterPlaylist {
            for mhod in master.mhods {
                guard let index = BrowseIndex(mhod: mhod) else { continue }
                guard index.isPermutation(of: remaining) else {
                    throw CommandError("the table '\(index.criterion.label)' is not a permutation of \(remaining) tracks")
                }
            }
        }
        let living = Set(updated.tracks.map(\.uniqueID))
        for section in updated.sections {
            guard case .playlists(let playlists) = section.content else { continue }
            for playlist in playlists where !playlist.entries.allSatisfy({ living.contains($0.trackID) }) {
                throw CommandError("the playlist '\(playlist.name ?? "?")' points to a removed track")
            }
        }

        announce(try await onDevice.write(updated, changes: changes, note: "removing \(plan.items.count) tracks"))
    }
}
