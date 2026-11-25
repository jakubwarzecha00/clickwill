import ClickwillShared
import Foundation

/// What the user picked in Settings: follow the Mac, always light or dark, or one of their
/// own themes.
public enum ThemeChoice: Hashable, Sendable {
    case system, light, dark
    case custom(UUID)

    /// The choices of the segmented control; a custom theme is picked from the list below it.
    public static let builtIn: [ThemeChoice] = [.system, .light, .dark]

    /// Parsed by hand: `system`, `light`, `dark` or `custom:<UUID>`. Anything else is nil.
    public init?(storageValue: String) {
        switch storageValue {
        case "system": self = .system
        case "light": self = .light
        case "dark": self = .dark
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
        case .custom(let id): "custom:" + id.uuidString
        }
    }

    /// The title in the segmented control; nil for a custom theme.
    public var title: String? {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
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
        }
    }
}
