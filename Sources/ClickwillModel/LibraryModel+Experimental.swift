import Foundation
import ITDBKit

/// Diagnostics and experimental writing: the policy a loaded device gets, the permission
/// after a passed diagnostic run, and the question after the first experimental write.
extension LibraryModel {

    /// The device with the `WritePolicy` from `permissions` - the one place the model sets it.
    func withWritePolicy(_ source: LibrarySource) -> LibrarySource {
        guard case .device(var device) = source else { return source }
        device.writePolicy = permissions.policy(for: device)
        return .device(device)
    }

    /// Runs every diagnostic check on the loaded iPod. Reads only.
    public func runDiagnostics() -> Diagnostics? {
        guard let device else { return nil }
        return Diagnostics.run(on: device, isMusicRunning: environment.isMusicRunning)
    }

    /// The Rockbox installation on the loaded iPod, when there is one.
    public var rockbox: RockboxInstallation? {
        device.flatMap { RockboxInstallation.detect(at: $0.volume.mountPoint) }
    }

    /// Reads every song file and compares it with the library (`RockboxReport`).
    public func rockboxReport(progress: (@Sendable (Int, Int) -> Void)? = nil) async -> RockboxReport? {
        guard let device, let library, let rockbox else { return nil }
        return await RockboxReport.build(library: library, paths: device.paths, installation: rockbox, progress: progress)
    }

    /// Allows experimental writing on the loaded iPod and loads it again with the new policy.
    /// Only a device that passed `diagnostics` - checked again here, not trusted from the caller.
    public func allowExperimentalWriting() async throws {
        guard let device else { throw WriteBlocked.notFromDevice }
        try permissions.allow(device, diagnostics: Diagnostics.run(on: device, isMusicRunning: environment.isMusicRunning))
        await load(.device(device))
    }

    /// Takes the permission back and loads the iPod again, read-only.
    public func revokeExperimentalWriting(identity: String) async {
        permissions.revoke(identity: identity)
        if let device, device.identity == identity { await load(.device(device)) }
    }

    /// After the switch or a permission changed: loads the iPod again with the policy it has now.
    /// With changes waiting it doesn't reload - they would be lost; the write refuses instead
    /// (`WriteBlocked.permissionChanged`).
    public func reapplyWritePolicy() async {
        guard let device, permissions.policy(for: device) != device.writePolicy, !hasPendingChanges else { return }
        await load(.device(device))
    }

    /// The question "Were the changes visible on the iPod?" for the loaded device, after an
    /// experimental write it hasn't been answered for yet.
    public var experimentalWriteAwaitingAnswer: ExperimentalPermissions.WriteRecord? {
        device.flatMap { permissions.grant(for: $0)?.awaitingAnswer }
    }
}
