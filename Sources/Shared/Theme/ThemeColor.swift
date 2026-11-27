import SwiftUI

/// A color named by its job (`Theme.fg`, `Theme.accent`), taken from the theme of the window
/// at the moment it is drawn. A view keeps the name, and a change of theme repaints it.
public struct ThemeColor: ShapeStyle, Sendable {
    private let pick: @Sendable (ThemePalette) -> Color
    private let alpha: Double

    public init(_ pick: @escaping @Sendable (ThemePalette) -> Color) {
        self.init(pick, alpha: 1)
    }

    private init(_ pick: @escaping @Sendable (ThemePalette) -> Color, alpha: Double) {
        self.pick = pick
        self.alpha = alpha
    }

    /// The same color, more transparent - for any palette, not only the current one.
    public func opacity(_ opacity: Double) -> ThemeColor {
        ThemeColor(pick, alpha: alpha * opacity)
    }

    /// The color in a given palette, where an API needs a `Color` (a gradient, glass tint).
    public func color(in palette: ThemePalette) -> Color {
        alpha == 1 ? pick(palette) : pick(palette).opacity(alpha)
    }

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color(in: environment.appTheme.palette).resolve(in: environment)
    }

    /// Nothing, in places that choose between a theme color and none.
    public static let clear = ThemeColor { _ in .clear }
}

public extension View {
    /// The tint of system controls from the theme. `tint` with a `Color`, as system controls
    /// drawn by AppKit expect.
    func themeTint(_ color: ThemeColor) -> some View {
        modifier(ThemeTint(color: color))
    }
}

private struct ThemeTint: ViewModifier {
    let color: ThemeColor
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.tint(color.color(in: theme.palette))
    }
}
