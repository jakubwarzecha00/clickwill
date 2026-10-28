import AppKit
import Combine
import Observation
import ClickwillModel

/// Watches the connected iPod for the whole time the app runs, regardless
/// of which view is on screen: loads the iPod when it appears,
/// and takes the library down when it disappears.
///
/// It leaves the views state to observe: the mounted volumes (`volumes`).
/// A library taken down is visible in the model itself (`LibraryModel.source`). The views
/// do not need to know the system's timers or notifications.
@MainActor
@Observable
final class DeviceMonitor {
    /// The mounted volumes. The window compares the previous set with the new one: a new
    /// volume is e.g. an inserted disc, a missing one - an ejected one.
    private(set) var volumes: Set<URL>

    @ObservationIgnored private let model: LibraryModel
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []

    init(model: LibraryModel) {
        self.model = model
        // Right away, before the window: the set found at launch is not a change -
        // a disc that was already in the drive does not switch the screen.
        volumes = Self.mountedVolumes()
    }

    /// Starts observing; a second call does nothing.
    func start() {
        guard subscriptions.isEmpty else { return }
        // Music may be closed outside the app - we refresh the preflight on
        // every return to the window, not only when loading.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.appBecameActive() }
            .store(in: &subscriptions)
        // The unmount notification may not arrive - an iPod pulled out of the socket
        // does not always end as a clean unmount, and the app may be in the background
        // at the time. That is why we also simply check for the device every so often:
        // it is a single question about whether a folder exists.
        Timer.publish(every: 2, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.tick() }
            .store(in: &subscriptions)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didMountNotification)
            .sink { [weak self] _ in self?.volumeMounted() }
            .store(in: &subscriptions)
        workspace.publisher(for: NSWorkspace.didUnmountNotification)
            .sink { [weak self] _ in self?.volumeUnmounted() }
            .store(in: &subscriptions)
    }

    private func appBecameActive() {
        model.refreshConnectedChoices()
        dropDeviceIfGone()
        model.refreshPreflight()
        loadDeviceIfIdle()
    }

    private func tick() {
        // Cheap, as long as the set of volumes does not change - see DeviceConnections.
        model.refreshConnectedChoices()
        dropDeviceIfGone()
        refreshVolumes()
        // The same pulse looks for a device. A volume is sometimes ready only a moment after
        // the mount notification, and the first attempt hits nothing - without
        // retrying, the screen stayed on "no iPod" even with the cable connected.
        // Only from the empty state: a failed read is not retried every two
        // seconds, because that would mean grinding through the whole database over and over.
        if model.state == .empty { loadDeviceIfIdle() }
    }

    /// An iPod connected after launch: the volume mounts, so we load it without a restart.
    private func volumeMounted() {
        model.refreshConnectedChoices()
        loadDeviceIfIdle()
        refreshVolumes()
    }

    /// An iPod disconnected: the "no device" state instead of a library that
    /// can no longer be written or played anyway.
    private func volumeUnmounted() {
        model.refreshConnectedChoices()
        dropDeviceIfGone()
        refreshVolumes()
    }

    /// Assigned only on a change - the pulse every two seconds does not wake the views.
    private func refreshVolumes() {
        let now = Self.mountedVolumes()
        if now != volumes { volumes = now }
    }

    private static func mountedVolumes() -> Set<URL> {
        Set(FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? [])
    }

    private func dropDeviceIfGone() {
        _ = model.deviceDisconnected()
    }

    /// Without a loaded library (no device or a read error) we try
    /// to load the connected iPod. A loaded library is left alone - the user
    /// may have unsaved changes.
    private func loadDeviceIfIdle() {
        switch model.state {
        case .empty, .failed:
            guard let source = model.connections.preferredSource() else { return }
            Task { await model.load(source) }
        case .loading, .loaded:
            break
        }
    }
}
