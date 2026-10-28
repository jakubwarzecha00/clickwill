import Foundation
import Observation
import ITDBKit

/// Connected iPods: the list to choose from on the device card, which one to load when
/// several are connected (the last used), and the memory of that choice.
///
/// Device discovery (`Discovery`) and the memory of the last iPod (`LastUsed`)
/// are injected - by default the system and `UserDefaults`, fakes in tests.
@MainActor
@Observable
public final class DeviceConnections {

    /// How we know what is connected.
    public struct Discovery: Sendable {
        /// Mount points of volumes that look like an iPod - a cheap question.
        public var mountPoints: @Sendable () -> [URL]
        /// Connected iPods that can be opened - asks the firmware over USB.
        public var devices: @Sendable () -> [IPodDevice]

        public init(mountPoints: @escaping @Sendable () -> [URL], devices: @escaping @Sendable () -> [IPodDevice]) {
            self.mountPoints = mountPoints
            self.devices = devices
        }

        /// Volumes mounted in the system. A volume without a database (an iPod still
        /// mounting, an empty disk with an iPod_Control folder) is skipped.
        public static let system = Discovery(
            mountPoints: { IPodVolume.mounted().map(\.mountPoint) },
            devices: { IPodVolume.mounted().compactMap { try? IPodDevice.open($0, scope: LibrarySource.writeScope) } })
    }

    /// The last loaded iPod (`IPodDevice.identity`).
    public struct LastUsed: Sendable {
        public var load: @Sendable () -> String?
        public var save: @Sendable (String) -> Void

        public init(load: @escaping @Sendable () -> String?, save: @escaping @Sendable (String) -> Void) {
            self.load = load
            self.save = save
        }

        public static let key = "clickwill.lastIPod"
        public static let standard = LastUsed(load: { UserDefaults.standard.string(forKey: key) },
                                              save: { UserDefaults.standard.set($0, forKey: key) })
    }

    /// iPods to choose from. Refreshed only when the set of volumes changes:
    /// opening an iPod asks the firmware over USB, so we do not do it every two seconds.
    public private(set) var choices: [IPodChoice] = []
    @ObservationIgnored private var mounts: [URL]?
    /// `--demo-ipod`: a list for screenshots instead of real devices.
    public var demoChoices: [IPodChoice] = [] {
        didSet { choices = demoChoices }
    }

    private let discovery: Discovery
    private let lastUsed: LastUsed

    public init(discovery: Discovery = .system, lastUsed: LastUsed = .standard) {
        self.discovery = discovery
        self.lastUsed = lastUsed
    }

    /// The iPod to load: the last used one, if it is among the connected ones;
    /// otherwise the first.
    public func preferredSource() -> LibrarySource? {
        Self.preferred(among: discovery.devices(), lastUsed: lastUsed.load()).map { .device($0) }
    }

    /// The loaded iPod - the next launch will start from it.
    func remember(_ device: IPodDevice) { lastUsed.save(device.identity) }

    /// `loaded`: the loaded source and the name from its library - we do not read it
    /// from disk a second time. `force`: after opening the chooser, because a write may
    /// have changed the used space.
    func refresh(force: Bool, loaded: LibrarySource?, loadedName: String?) {
        guard demoChoices.isEmpty else { return }
        // A backup from disk (--snapshot) is not one of the connected iPods -
        // the list would mix it with real devices.
        if case .snapshot = loaded { choices = []; mounts = nil; return }
        let current = discovery.mountPoints()
        guard force || current != mounts else { return }
        mounts = current
        choices = discovery.devices().map { device in
            let name = (LibrarySource.device(device) == loaded ? loadedName : nil) ?? IPodChoice.storedName(of: device)
            return IPodChoice(device: device, name: name)
        }
    }

    /// The list item corresponding to the loaded source.
    func choice(for source: LibrarySource?, name: String?) -> IPodChoice? {
        guard let source else { return nil }
        if let listed = choices.first(where: { $0.source == source }) { return listed }
        if case .device(let device) = source { return IPodChoice(device: device, name: name) }
        return nil
    }

    nonisolated static func preferred(among devices: [IPodDevice], lastUsed: String?) -> IPodDevice? {
        devices.first { $0.identity == lastUsed } ?? devices.first
    }
}
