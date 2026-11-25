import Foundation
import Observation
import ClickwillShared

/// The theme the app's windows show: the user's choice, and with System, the Mac's setting.
///
/// The themes module is a plug: only the app's module list (`Modules.swift`) knows it, and
/// without it every window falls back to `AppTheme.standard`.
@MainActor
@Observable
public final class ThemeStore {
    /// Kept between launches; a launch for screenshots may set another one for itself.
    public var choice: ThemeChoice {
        didSet { storage.save(choice.rawValue) }
    }

    @ObservationIgnored private let storage: Storage
    private let system: SystemAppearance

    /// - Parameter launchChoice: this process only (`--appearance`); the saved choice stays.
    public init(storage: Storage, system: SystemAppearance, launchChoice: ThemeChoice? = nil) {
        self.storage = storage
        self.system = system
        choice = launchChoice ?? storage.load().flatMap(ThemeChoice.init(rawValue:)) ?? .system
    }

    public var current: AppTheme {
        AppTheme(palette: choice.palette(systemIsDark: system.isDark))
    }

    /// Where the choice is kept: `UserDefaults` in the app, memory in tests and demo mode.
    public struct Storage: Sendable {
        public var load: @Sendable () -> String?
        public var save: @Sendable (String) -> Void

        public init(load: @escaping @Sendable () -> String?, save: @escaping @Sendable (String) -> Void) {
            self.load = load
            self.save = save
        }

        public static let key = "clickwill.appearance"
        public static let standard = Storage(load: { UserDefaults.standard.string(forKey: key) },
                                             save: { UserDefaults.standard.set($0, forKey: key) })

        /// Nothing survives the process.
        public static func memory(_ value: String? = nil) -> Storage {
            let box = Box(value: value)
            return Storage(load: { box.value }, save: { box.value = $0 })
        }

        private final class Box: @unchecked Sendable {
            var value: String?
            init(value: String?) { self.value = value }
        }
    }
}
