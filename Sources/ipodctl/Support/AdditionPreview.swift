import Foundation
import ITDBKit
import ClickwillModel

/// A preview of the database after adding, with invariant checks, and with `--apply` the write:
/// a backup, the files, the database. Shared by `add` and `copy` - adding is
/// risky enough that we do not want two paths that could drift apart.
func previewAndApply(_ additions: [PendingAddition], to onDevice: DeviceLibrary, note: String) async throws {
    let (device, library) = (onDevice.device, onDevice.library)
    // Preview: we assemble the database in memory and check the invariants.
    var simulated = library
    for (offset, addition) in additions.enumerated() {
        var draft = addition.draft
        if let target = addition.target { draft.kind = target.kindForDevice }
        draft.relativePath = "iPod_Control/Music/F00/SIM\(offset).\(draft.kind.fileExtension)"
        simulated = try simulated.addingTracks([draft])
    }
    let before = library.tracks.count
    print("\nDatabase preview after adding:")
    report("Invariants", [
        ("tracks", "\(before) -> \(simulated.tracks.count)"),
        ("albums (mhia)", "\(library.albums.count) -> \(simulated.albums.count)"),
    ])
    var ok = true
    for section in simulated.sections {
        guard case .playlists(let playlists) = section.content else { continue }
        for playlist in playlists where playlist.isMaster {
            if playlist.entries.count != simulated.tracks.count {
                print("  ERROR: the master playlist has \(playlist.entries.count) entries for \(simulated.tracks.count) tracks"); ok = false
            }
            for mhod in playlist.mhods {
                if let index = BrowseIndex(mhod: mhod) {
                    let good = index.isPermutation(of: simulated.tracks.count)
                    print("  table \(index.criterion.rawValue): \(index.entries.count) positions, permutation: \(good ? "yes" : "NO")")
                    if !good { ok = false }
                }
                if let jump = AlphabetJumpTable(mhod: mhod) {
                    let covered = jump.entries.reduce(0) { $0 + Int($1.count) }
                    let good = covered == simulated.tracks.count
                    print("  bar \(jump.criterion.rawValue): covers \(covered)/\(simulated.tracks.count)\(good ? "" : "  ERROR")")
                    if !good { ok = false }
                }
            }
        }
    }
    // Write and read back - the same as the device will do.
    let bytes = ITunesDBWriter.serialize(simulated)
    let reparsed = try ITunesDBParser.parse(bytes)
    let same = ITunesDBWriter.serialize(reparsed) == bytes
    print("  write -> read -> write identical: \(same ? "yes" : "NO")")
    if !same { ok = false }
    if device.supportsWriting {
        let signed = try device.signer.sign(bytes)
        print("  signature \(device.format.name): \(signed.count == bytes.count ? "computed" : "ERROR")")
    } else {
        print("  writing to this iPod: BLOCKED - \(device.readOnlyReason?.description ?? "?")")
    }
    print("  database size: \(formatted(bytes: Int64(library.sourceByteCount))) -> \(formatted(bytes: Int64(bytes.count)))")
    guard ok else { throw CommandError("the invariants did not pass - writing nothing") }

    guard onDevice.call.has("--apply") else { print("\n  That was a preview. To write: add --apply"); return }
    print("\nWriting to: \(device.model.name) [\(device.identity)] at \(device.volume.mountPoint.path)")
    // The database the preview started from. A different one at write time - a refusal.
    announce(try await onDevice.write(library, changes: ChangeSet(additions: additions), note: note))
}
