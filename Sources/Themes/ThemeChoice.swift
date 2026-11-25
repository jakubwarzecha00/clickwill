import ClickwillShared
import Foundation

/// What the user picked in Settings: follow the Mac, always light or dark, the Vice theme,
/// or one of their own themes.
public enum ThemeChoice: Hashable, Sendable {
    case system, light, dark, vice
    case custom(UUID)

    /// The tiles before the user's own themes in Settings.
    public static let builtIn: [ThemeChoice] = [.system, .light, .dark, .vice]

    /// Parsed by hand: `system`, `light`, `dark`, `vice` or `custom:<UUID>`. Anything else
    /// is nil.
    public init?(storageValue: String) {
        switch storageValue {
        case "system": self = .system
        case "light": self = .light
        case "dark": self = .dark
        case "vice": self = .vice
        default:
            let prefix = "custom:"
            guard storageValue.hasPrefix(prefix),
                  let id = UUID(uuidString: String(storageValue.dropFirst(prefix.count))) else { return nil }
            self = .custom(id)
        }
    }

    public var storageValue: String {
        switch self {
        case .system: "system"
        case .light: "light"
        case .dark: "dark"
        case .vice: "vice"
        case .custom(let id): "custom:" + id.uuidString
        }
    }

    /// The title under a built-in tile; nil for a custom theme, which has its own name.
    public var title: String? {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .vice: "Vice"
        case .custom: nil
        }
    }

    /// The palette of a built-in choice while the Mac is dark (`systemIsDark`) or light.
    /// A custom theme's palette comes from the library (`ThemeStore`); here it is the
    /// System one, which is also what a missing custom theme falls back to.
    public func palette(systemIsDark: Bool) -> ThemePalette {
        switch self {
        case .system, .custom: systemIsDark ? .dark : .light
        case .light: .light
        case .dark: .dark
        case .vice: .vice
        }
    }

    /// The moving picture behind the scene that comes with a built-in choice.
    var sceneBackdrop: SceneBackdrop? {
        self == .vice ? .sunset : nil
    }
}
