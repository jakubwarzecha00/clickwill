import SwiftUI
import ClickwillShared

/// A theme the user made or imported: a name and three colors. The rest of its palette is
/// worked out from them (`ThemeDerivation`).
public struct CustomTheme: Identifiable, Sendable, Equatable {
    /// The colors a new theme starts from: those of the built-in light or dark theme.
    public enum Start: Sendable {
        case light, dark

        var colors: [String: String] {
            switch self {
            case .light: ["accent": "#2F6AA8", "background": "#F5F5F7", "scene": "#F2F2F4"]
            case .dark: ["accent": "#7D9DC4", "background": "#1C1C1E", "scene": "#0B0B0D"]
            }
        }
    }

    /// Also the name of its file in the library; never taken from a file's content.
    public let id: UUID
    public var name: String
    /// Every token's color by its key, as opaque `#RRGGBB`. A color missing or unreadable in
    /// `colors` comes from `start`; keys that are not tokens are dropped.
    public private(set) var colors: [String: String]

    public init(id: UUID = UUID(), name: String, start: Start = .dark, colors: [String: String] = [:]) {
        self.id = id
        self.name = name
        var kept = start.colors
        for token in ThemeToken.all {
            if let text = colors[token.key], let color = HexColor.color(text) {
                kept[token.key] = HexColor.string(color, opaque: true)
            }
        }
        self.colors = kept
    }

    public var palette: ThemePalette {
        ThemeDerivation.palette(accent: color(.accent), background: color(.background), scene: color(.scene))
    }

    public func color(_ token: ThemeToken) -> Color {
        colors[token.key].flatMap(HexColor.color) ?? .clear
    }

    public mutating func set(_ color: Color, for token: ThemeToken) {
        colors[token.key] = HexColor.string(color, opaque: true)
    }

    /// A copy under a new identity, named "<name> Copy" within the name limit.
    public func duplicate() -> CustomTheme {
        let suffix = " Copy"
        let stem = String(name.prefix(ThemeName.maxLength - suffix.count))
        return CustomTheme(name: stem + suffix, colors: colors)
    }
}

/// A theme's name as shown and kept: no control or text-direction characters, at most
/// 60 characters, never empty.
public enum ThemeName {
    public static let maxLength = 60
    public static let untitled = "Untitled Theme"

    public static func clean(_ text: String) -> String {
        let directional: [ClosedRange<UInt32>] = [0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069]
        let scalars = text.unicodeScalars.filter { scalar in
            scalar.properties.generalCategory != .control
                && !directional.contains { $0.contains(scalar.value) }
        }
        let kept = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(kept.prefix(maxLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? untitled : cut
    }

    /// A name for an exported file: no slashes or colons, which a file name cannot hold.
    public static func fileName(_ name: String) -> String {
        let safe = clean(name).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return safe
    }
}
