import ClickwillModel
import ITDBKit

/// What the Overview screen says about the device and the library - the rows separate from
/// the view, which only lays them out.
enum OverviewFacts {
    typealias Row = (label: String, value: String)

    struct Section: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    @MainActor static func sections(of model: LibraryModel) -> [Section] {
        var sections: [Section] = []
        if let device = model.device {
            sections.append(Section(title: "Device", rows: [
                ("Name", model.deviceName ?? device.volume.name),
                ("Model", device.catalogEntry.map(\.name)
                            ?? device.model.modelNumber.map { "\(device.model.name) (\($0))" }
                            ?? "\(device.model.name) (model number not reported)"),
                ("Volume", device.volume.mountPoint.path),
                ("FireWire GUID", device.fireWireID?.hex ?? missingGUID(device)),
                ("Database format", "\(device.format.name), \(device.format.headerLength)-byte header, version \(device.format.version)"),
                ("Writing", device.supportsWriting ? "Allowed" : "Refused: \(ErrorPresenter.readOnlyMessage(device.readOnlyReason))"),
                ("Capacity", "\(device.volume.usedCapacity.gigabytes) used of \(device.volume.totalCapacity.gigabytes)"),
            ]))
            if let preflight = model.preflight() {
                sections.append(Section(title: "Before Writing", rows: preflight.issues.isEmpty
                    ? [("Status", clearPreflight)]
                    : preflight.issues.map { ("Issue", ErrorPresenter.message(for: $0)) }))
            }
        } else {
            sections.append(Section(title: "Source", rows: [("Snapshot", model.source?.displayName ?? "None"), ("Writes", "disabled")]))
        }
        sections.append(Section(title: "Library", rows: [
            ("Albums", "\(model.albums.count)"),
            ("Albums with a cover", "\(model.albumsWithCover) of \(model.albums.count)"),
            ("Songs", "\(model.trackCount)"),
            ("Entries without a file", "\(model.albums.reduce(0) { $0 + $1.missingFiles })"),
            ("Cover images", "\(model.artwork?.images.count ?? 0)"),
        ]))
        return sections
    }

    /// A missing GUID means something different on a Classic than on an older iPod:
    /// a database signed with hash58 requires it, it just could not be read.
    private static func missingGUID(_ device: IPodDevice) -> String {
        device.format.signing == .hash58
            ? "not found, needed to sign this iPod's database"
            : "none, this generation has no GUID"
    }

    private static let clearPreflight = "Clear: Music is closed, no pending play counts"
}
