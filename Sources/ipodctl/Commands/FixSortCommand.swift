import Foundation
import ITDBKit

/// `fix-sort [--apply]` - repairing sort fields that split albums into several covers.
enum FixSortCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let changes = SortFieldRepair.plan(for: library)
        guard !changes.isEmpty else {
            print("No sort fields split any albums. Nothing to repair.")
            return
        }

        let albums = Set(changes.map(\.album))
        report("Sort field repair", [
            ("albums", "\(albums.count)"),
            ("tracks", "\(Set(changes.map(\.trackID)).count)"),
            ("field changes", "\(changes.count)"),
        ])
        for album in albums.sorted() {
            print("\n  \(album)")
            for change in changes where change.album == album {
                print("      \(change.title)")
                print("          \(change.summary)")
            }
        }

        guard call.has("--apply") else {
            print("\n  That was a preview. To write: ipodctl fix-sort --apply")
            return
        }

        let updated = SortFieldRepair.apply(changes, to: library)
        announce(try await onDevice.write(updated, note: "sort field repair in \(albums.count) albums"))
    }
}
