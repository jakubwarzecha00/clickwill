import ClickwillShared

/// What the user picked in Settings: follow the Mac, or always light or dark.
public enum ThemeChoice: String, CaseIterable, Sendable, Identifiable {
    case system, light, dark

    public var id: Self { self }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The palette for this choice while the Mac is dark (`systemIsDark`) or light.
    public func palette(systemIsDark: Bool) -> ThemePalette {
        switch self {
        case .system: systemIsDark ? .dark : .light
        case .light: .light
        case .dark: .dark
        }
    }
}
