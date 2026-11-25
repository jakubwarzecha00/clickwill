import AppKit
import Observation

/// Whether the Mac is set to dark: the app's own appearance, which the app never sets, so it
/// is always the system's. The windows' appearance cannot tell, because a theme forces it.
@MainActor
@Observable
public final class SystemAppearance {
    public private(set) var isDark: Bool
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// A fixed answer, for tests.
    public init(isDark: Bool) {
        self.isDark = isDark
    }

    /// Follows the Mac's setting while the app runs.
    public static func live() -> SystemAppearance {
        let app = NSApplication.shared
        let system = SystemAppearance(isDark: isDark(app.effectiveAppearance))
        system.observation = app.observe(\.effectiveAppearance) { [weak system] _, _ in
            // The change can arrive off the main thread; the appearance is read on it.
            Task { @MainActor in
                system?.isDark = isDark(NSApplication.shared.effectiveAppearance)
            }
        }
        return system
    }

    /// A change of the Mac's setting, in tests.
    func setForTesting(isDark: Bool) {
        self.isDark = isDark
    }

    /// High-contrast dark counts as dark: only its best match is `darkAqua`, not its name.
    nonisolated static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
