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
        didSet { storage.save(choice.storageValue) }
    }

    /// The user's own themes; nil when their folder could not be made, and then only the
    /// built-in themes are offered.
    public let library: ThemeLibrary?
    /// The theme open on the editor page; set before the page is shown.
    public var editing: ThemeEditing?
    @ObservationIgnored private let storage: Storage
    private let system: SystemAppearance

    /// - Parameter launchChoice: this process only (`--appearance`); the saved choice stays.
    public init(storage: Storage, system: SystemAppearance, library: ThemeLibrary? = nil,
                launchChoice: ThemeChoice? = nil) {
        self.storage = storage
        self.system = system
        self.library = library
        choice = launchChoice ?? storage.load().flatMap(ThemeChoice.init(storageValue:)) ?? .system
    }

    /// A chosen custom theme that is gone or does not open shows the System look, without
    /// changing the saved choice: the file may come back.
    public var current: AppTheme {
        if case .custom(let id) = choice, let theme = library?.theme(id) {
            return AppTheme(palette: theme.palette)
        }
        return AppTheme(palette: choice.palette(systemIsDark: system.isDark), sceneBackdrop: choice.sceneBackdrop)
    }

    /// Saves a theme from the editor. A new theme is also chosen, so the window shows it.
    public func save(_ theme: CustomTheme, choose: Bool) throws(ThemeFileError) {
        guard let library else { throw .cannotSave }
        try library.save(theme)
        if choose { choice = .custom(theme.id) }
    }

    /// Deleting the chosen theme is the user's doing, so the choice goes back to System.
    public func delete(_ id: UUID) throws(ThemeFileError) {
        guard let library else { return }
        try library.delete(id)
        if choice == .custom(id) { choice = .system }
    }

    /// A theme on the editor page, and whether Save adds it.
    public struct ThemeEditing: Identifiable, Equatable, Sendable {
        public let theme: CustomTheme
        public let isNew: Bool
        public var id: UUID { theme.id }

        public init(theme: CustomTheme, isNew: Bool) {
            self.theme = theme
            self.isNew = isNew
        }
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
