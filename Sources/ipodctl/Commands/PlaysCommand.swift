import Foundation
import ITDBKit

/// `plays [--merge [--apply]]` - statistics counted by the iPod; `--merge`
/// merges them into the database and deletes the file.
enum PlaysCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        guard let counts = try device.readPlayCounts() else {
            print("No Play Counts file - the iPod has counted nothing since the last sync.")
            return
        }
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let merge = PlayCounts.merged(into: library.tracks, from: counts)
        report("Statistics waiting to be merged", [
            ("entries in the file", "\(counts.entries.count)"),
            ("non-empty", "\(counts.pending.count)"),
            ("tracks with a change", "\(merge.changed)"),
        ])
        let byIndex = Dictionary(uniqueKeysWithValues: library.tracks.enumerated().map { ($0.offset, $0.element) })
        for (index, entry) in counts.pending.prefix(20) {
            let track = byIndex[index]
            let name = "\(track?.artist ?? "?") - \(track?.title ?? "?")"
            var parts: [String] = []
            if entry.playCount > 0 { parts.append("+\(entry.playCount) plays (in the database \(track?.playCount ?? 0))") }
            if let played = entry.lastPlayed { parts.append("last \(played.formatted(date: .abbreviated, time: .shortened))") }
            if entry.lastSkipped != nil { parts.append("skipped") }
            print("  \(name): \(parts.joined(separator: ", "))")
        }
        if counts.pending.count > 20 { print("  ... and \(counts.pending.count - 20) more") }

        guard call.has("--merge") else { return }
        guard merge.changed > 0 else {
            print("\n  Nothing to merge.")
            return
        }
        guard call.has("--apply") else {
            print("\n  That was a preview. To merge into the database and delete the file: add --apply")
            return
        }

        // The writer merges pending plays itself - here it is enough to write the database unchanged.
        announce(try await onDevice.write(library, note: "merging plays"))
    }
}
