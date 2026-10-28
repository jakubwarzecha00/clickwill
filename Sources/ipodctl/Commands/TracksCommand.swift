import Foundation
import ITDBKit

/// `tracks --album A [--move TRACK (--before TRACK | --after TRACK | --at N)] [--renumber] [--apply]`
/// - track order in an album; `--renumber` assigns 1..N according to the layout.
enum TracksCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        guard let album = call.value(for: "--album") else { throw CommandError("give --album NAME") }
        let onDevice = try DeviceLibrary(reading: device, for: call)
        var library = onDevice.library
        let order = try library.trackOrder(album: album)

        /// A track by its (exact) title or by its identifier.
        func resolve(_ spec: String) throws -> UInt32 {
            if let id = UInt32(spec), order.contains(where: { $0.uniqueID == id }) { return id }
            let hits = order.filter { $0.title == spec }
            guard hits.count == 1 else {
                throw CommandError(hits.isEmpty ? "the album has no track '\(spec)'" : "the title '\(spec)' matches \(hits.count) tracks - give an id")
            }
            return hits[0].uniqueID
        }

        var changed = false
        if let spec = call.value(for: "--move") {
            let id = try resolve(spec)
            let target: TrackOrderTarget
            if let other = call.value(for: "--before") { target = .before(try resolve(other)) }
            else if let other = call.value(for: "--after") { target = .after(try resolve(other)) }
            else if let at = call.value(for: "--at").flatMap(Int.init) { target = .atIndex(at) }
            else { throw CommandError("give --before TRACK, --after TRACK or --at N") }
            library = try library.movingTrack(id, in: album, target)
            changed = true
        }
        if call.has("--renumber") {
            library = try library.renumberingTracks(album: album)
            changed = true
        }

        let after = try library.trackOrder(album: album)
        print("\(album)  -  \(after.count) tracks\(changed ? "  (after the change)" : "")\n")
        for (position, track) in after.enumerated() {
            let number = track.trackNumber == 0 ? " -" : String(format: "%2d", track.trackNumber)
            let disc = track.discNumber > 0 ? " d\(track.discNumber)" : ""
            print("  \(String(format: "%2d", position + 1)).  no. \(number)\(disc)   \(track.title ?? "?")   [id \(track.uniqueID)]")
        }

        guard changed else { return }
        guard call.has("--apply") else {
            print("\n  That was a preview. To write: add --apply")
            return
        }
        announce(try await onDevice.write(library, note: "track order in album '\(album)'"))
    }
}
