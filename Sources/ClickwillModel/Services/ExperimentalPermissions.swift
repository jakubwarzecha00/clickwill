import Foundation
import Observation
import ITDBKit

/// Who may write to an iPod outside the confirmed models: the Experimental iPods switch in
/// Settings, one permission per device, and Developer Mode. Kept on the Mac, never on the iPod.
///
/// A permission belongs to the device identity, its USB product and its firmware version.
/// A firmware update makes it a different device as far as we know, so the permission lapses.
/// Turning the switch off takes back every permission.
@MainActor
@Observable
public final class ExperimentalPermissions {

    /// One allowed device.
    public struct Grant: Codable, Sendable, Equatable, Identifiable {
        public var id: String { identity }
        /// `IPodDevice.identity` when allowed; matched against all `IPodDevice.identities`.
        public let identity: String
        public let usbProductID: UInt16
        public let firmwareVersion: String?
        /// For the list in Settings.
        public let modelName: String
        public let allowedAt: Date
        /// The backup from before the first experimental write - kept until deleted by hand.
        public var firstBackupID: String?
        /// The last experimental write, until the user says whether the iPod showed it.
        public var awaitingAnswer: WriteRecord?
        /// The last answer: whether the iPod showed the changes.
        public var lastAnswer: Bool?
    }

    public struct WriteRecord: Codable, Sendable, Equatable {
        public let date: Date
        public let changes: Int
    }

    /// Where the switch and the permissions are kept - `UserDefaults` in the app, memory in tests.
    public struct Storage: Sendable {
        public var load: @Sendable () -> Data?
        public var save: @Sendable (Data) -> Void

        public init(load: @escaping @Sendable () -> Data?, save: @escaping @Sendable (Data) -> Void) {
            self.load = load
            self.save = save
        }

        public static let key = "clickwill.experimentalIPods"
        public static let standard = Storage(load: { UserDefaults.standard.data(forKey: key) },
                                             save: { UserDefaults.standard.set($0, forKey: key) })

        /// Nothing survives the process - for tests and demo mode.
        public static func memory() -> Storage {
            let box = Box()
            return Storage(load: { box.data }, save: { box.data = $0 })
        }

        private final class Box: @unchecked Sendable { var data: Data? }
    }

    private struct Saved: Codable {
        var enabled: Bool
        var grants: [Grant]
    }

    /// The switch in Settings › Experimental iPods. Turning it off also ends Developer Mode.
    public var isEnabled: Bool {
        didSet {
            if !isEnabled {
                grants = []
                developerMode = false
            }
            persist()
        }
    }
    public private(set) var grants: [Grant]
    /// Developer Mode: in Settings › Experimental iPods after a warning, and from `--developer-mode`
    /// in a Debug build. Not stored - it ends when the app quits.
    public var developerMode = false

    private let storage: Storage

    public init(storage: Storage = .standard) {
        self.storage = storage
        let saved = storage.load().flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        isEnabled = saved?.enabled ?? false
        grants = saved?.enabled == true ? saved?.grants ?? [] : []
    }

    /// The policy the model gives this device when it loads it. A permission counts only
    /// while the standard policy refuses the model: once a release confirms it, the iPod
    /// writes as confirmed, with repairs and the Play Counts merge, and the permission rests.
    public func policy(for device: IPodDevice) -> WritePolicy {
        if developerMode { return .developer }
        var standard = device
        standard.writePolicy = .standard
        guard !standard.supportsWriting else { return .standard }
        return grant(for: device) != nil ? .experimental : .standard
    }

    /// The permission for this device, if it still matches its USB product and firmware.
    public func grant(for device: IPodDevice) -> Grant? {
        guard isEnabled, let usb = device.usb,
              let grant = grants.first(where: { device.identities.contains($0.identity) }),
              grant.usbProductID == usb.productID,
              grant.firmwareVersion == device.firmwareDescription?.firmwareVersion
        else { return nil }
        return grant
    }

    /// Allows experimental writing on a device that passed diagnostics. Replaces an
    /// older permission of the same identity (for example from before a firmware update).
    public func allow(_ device: IPodDevice, diagnostics: Diagnostics, now: Date = Date()) throws {
        guard isEnabled else { throw PermissionError.switchOff }
        guard diagnostics.allowsExperimentalWriting else { throw PermissionError.checksFailed }
        guard let usb = device.usb else { throw PermissionError.checksFailed }
        grants.removeAll { device.identities.contains($0.identity) }
        grants.append(Grant(identity: device.identity, usbProductID: usb.productID,
                            firmwareVersion: device.firmwareDescription?.firmwareVersion,
                            modelName: device.model.name, allowedAt: now))
        persist()
    }

    public func revoke(identity: String) {
        grants.removeAll { $0.identity == identity }
        persist()
    }

    /// After an experimental write: the question for the next connection, and the
    /// first backup to keep.
    func recordWrite(on device: IPodDevice, changes: Int, backupID: String, now: Date = Date()) {
        guard let index = grants.firstIndex(where: { device.identities.contains($0.identity) }) else { return }
        if grants[index].firstBackupID == nil { grants[index].firstBackupID = backupID }
        grants[index].awaitingAnswer = WriteRecord(date: now, changes: changes)
        persist()
    }

    /// The user's answer to "Were the changes visible on the iPod?".
    public func answer(_ shown: Bool, for identity: String) {
        guard let index = grants.firstIndex(where: { $0.identity == identity }) else { return }
        grants[index].awaitingAnswer = nil
        grants[index].lastAnswer = shown
        persist()
    }

    /// Backups that pruning must not delete for this device.
    func pinnedBackups(for device: IPodDevice) -> Set<String> {
        Set(grants.filter { device.identities.contains($0.identity) }.compactMap(\.firstBackupID))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(Saved(enabled: isEnabled, grants: grants)) else { return }
        storage.save(data)
    }

    public enum PermissionError: Error, Equatable {
        /// Settings › Experimental iPods is off.
        case switchOff
        /// Not every required diagnostic check passed.
        case checksFailed
    }
}
