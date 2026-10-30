import Foundation
import ITDBKit

/// One of the connected iPods to choose from on the card in the sidebar.
///
/// The choice appears only with two iPods at once - with one there is nothing
/// to choose. In `--demo` mode the list may come from the arguments
/// (`--demo-ipod`), so the chooser can be checked without two devices.
public struct IPodChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let source: LibrarySource
    public let name: String
    public let modelName: String
    public let totalCapacity: Int64
    public let usedCapacity: Int64
    /// A read-only iPod; the reason, when the device knows it.
    public let isReadOnly: Bool
    public let readOnlyReason: ReadOnlyReason?
    /// The policy the iPod writes under (`ExperimentalPermissions`) - the chooser shows an
    /// experimental iPod as one, not as read-only.
    public var writePolicy: WritePolicy = .standard
    /// Writing outside the confirmed models (`IPodDevice.writesOutsideConfirmedModels`).
    public var outsideConfirmedModels = false
    /// From the model catalog - for the drawing; `nil` when the catalog does not know this iPod.
    public var generation: IPodCatalog.Generation? = nil
    public var finish: IPodCatalog.Finish? = nil

    public var availableCapacity: Int64 { max(0, totalCapacity - usedCapacity) }

    public init(id: String, source: LibrarySource, name: String, modelName: String,
                totalCapacity: Int64, usedCapacity: Int64, isReadOnly: Bool = false, readOnlyReason: ReadOnlyReason? = nil) {
        self.id = id
        self.source = source
        self.name = name
        self.modelName = modelName
        self.totalCapacity = totalCapacity
        self.usedCapacity = usedCapacity
        self.isReadOnly = isReadOnly
        self.readOnlyReason = readOnlyReason
    }

    /// `name`: the name given to the iPod (from the database); without it - the volume name.
    public init(device: IPodDevice, name: String? = nil) {
        let entry = device.catalogEntry
        self.init(id: device.identity, source: .device(device), name: IPodChoice.displayName(name, volume: device.volume.name),
                  modelName: entry?.generation.name ?? device.model.name + (device.model.isConfirmed ? "" : "?"),
                  totalCapacity: device.volume.totalCapacity, usedCapacity: device.volume.usedCapacity,
                  isReadOnly: !device.supportsWriting, readOnlyReason: device.supportsWriting ? nil : device.readOnlyReason)
        generation = entry?.generation
        finish = entry?.finishOrDefault
        writePolicy = device.writePolicy
        outsideConfirmedModels = device.writesOutsideConfirmedModels
    }

    /// `--demo-ipod "<backup folder>|<name>|<model>|<GB total>|<GB used>[|<generation>:<color>[:<policy>]]"`,
    /// e.g. `...|classic3:black` - generation and color from `IPodCatalog` for the drawing;
    /// `...|video:black:experimental` shows the chooser's experimental badge.
    public init?(demoArgument: String) {
        let parts = demoArgument.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 || parts.count == 6, let total = Double(parts[3]), let used = Double(parts[4]) else { return nil }
        let gigabyte = 1_000_000_000.0
        self.init(id: "demo:" + parts[0], source: .snapshot(URL(fileURLWithPath: parts[0])), name: parts[1],
                  modelName: parts[2], totalCapacity: Int64(total * gigabyte), usedCapacity: Int64(used * gigabyte))
        if parts.count == 6 {
            let look = parts[5].split(separator: ":").map(String.init)
            generation = look.first.flatMap(IPodCatalog.Generation.init(rawValue:))
            finish = look.count > 1 ? IPodCatalog.Finish(rawValue: look[1]) : nil
            if look.count > 2, let policy = ["experimental": WritePolicy.experimental, "developer": .developer][look[2]] {
                writePolicy = policy
                outsideConfirmedModels = true
            }
        }
    }
}

extension IPodChoice {
    /// The name given to the iPod (e.g. "Anna's iPod"), and when there is none - the volume name
    /// Finder mounts it under (usually just "iPod").
    public static func displayName(_ name: String?, volume: String) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return volume }
        return name
    }

    /// The name from the database on the iPod, without reading the whole library.
    public static func storedName(of device: IPodDevice) -> String? {
        (try? Data(contentsOf: device.paths.iTunesDB)).flatMap { try? ITunesDBParser.deviceName(in: $0) }
    }
}
