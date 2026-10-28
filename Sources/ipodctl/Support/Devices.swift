import Foundation
import ITDBKit

/// An iPod by model name (`nano`, `classic`), GUID or path - of a volume
/// or a folder that looks like an iPod (a backup, a fake in tests). The model
/// and GUID do not change after reconnecting, the path does: after a USB
/// reset two iPods can come back with swapped names.
func resolveDevice(_ wanted: String) throws -> IPodDevice {
    let volumes = IPodVolume.mounted()
    let url = URL(fileURLWithPath: wanted).standardizedFileURL
    if let volume = volumes.first(where: { $0.mountPoint.standardizedFileURL.path == url.path }) ?? IPodVolume.at(url) {
        do { return try IPodDevice.open(volume) } catch { throw CommandError("\(error)") }
    }
    let devices = volumes.compactMap { try? IPodDevice.open($0) }
    let key = wanted.lowercased()
    let matches = devices.filter { $0.fireWireID?.hex.lowercased() == key || $0.model.name.lowercased().contains(key) }
    guard matches.count == 1 else {
        let known = devices.map { "\($0.model.name) [\($0.identity)] at \($0.volume.mountPoint.path)" }.joined(separator: "; ")
        throw CommandError("\(matches.isEmpty ? "no iPod matches" : "more than one iPod matches") '\(wanted)'. Connected: \(known)")
    }
    return matches[0]
}

/// The iPod given by `--volume`, and without the flag the only one connected. With several
/// iPods and no choice, a refusal: "the first on the list" is not a choice, and a write
/// to the wrong device is irreversible in practice.
func openDevice(_ call: Invocation) throws -> IPodDevice {
    if let wanted = call.value(for: "--volume") { return try resolveDevice(wanted) }
    let volumes = IPodVolume.mounted()
    guard volumes.count <= 1 else {
        throw CommandError("connected iPods: \(volumes.count) - choose one with --volume (nano, classic, GUID or path)")
    }
    do { return try IPodDevice.openFirst() } catch { throw CommandError("\(error)") }
}

/// Backups from the invocation environment (in tests - a temporary folder).
func openStore(_ call: Invocation) throws -> SnapshotStore {
    do { return try call.environment.backups() } catch { throw CommandError("\(error)") }
}
