import SwiftUI
import ClickwillShared

/// A theme the user made or imported: a base palette and the colors changed on top of it.
public struct CustomTheme: Identifiable, Sendable, Equatable {
    public enum Base: String, Sendable, CaseIterable, Identifiable {
        case light, dark

        public var id: Self { self }
        public var title: String { self == .light ? "Light" : "Dark" }
        public var palette: ThemePalette { self == .light ? .light : .dark }
    }

    /// Also the name of its file in the library; never taken from a file's content.
    public let id: UUID
    public var name: String
    public var base: Base
    /// Changed colors by token key, as `#RRGGBB` or `#RRGGBBAA`. A key not here comes from
    /// the base, so changing the base keeps every changed color.
    public private(set) var colors: [String: String]

    public init(id: UUID = UUID(), name: String, base: Base, colors: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.base = base
        self.colors = colors.filter { ThemeToken.named($0.key) != nil }
            .compactMapValues(HexColor.normalized)
    }

    public var palette: ThemePalette {
        var palette = base.palette
        for token in ThemeToken.all {
            if let hex = colors[token.key], let color = HexColor.color(hex) {
                palette[keyPath: token.keyPath] = color
            }
        }
        return palette
    }

    public func color(_ token: ThemeToken) -> Color {
        palette[keyPath: token.keyPath]
    }

    public func isChanged(_ token: ThemeToken) -> Bool {
        colors[token.key] != nil
    }

    public mutating func set(_ color: Color, for token: ThemeToken) {
        colors[token.key] = HexColor.string(color, opaque: !token.allowsOpacity)
    }

    /// Back to the base's color.
    public mutating func reset(_ token: ThemeToken) {
        colors[token.key] = nil
    }

    /// A copy under a new identity, named "<name> Copy" within the name limit.
    public func duplicate() -> CustomTheme {
        let suffix = " Copy"
        let stem = String(name.prefix(ThemeName.maxLength - suffix.count))
        return CustomTheme(name: stem + suffix, base: base, colors: colors)
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
