import SwiftUI
import ClickwillShared

/// A whole palette worked out from the three colors a user picks.
///
/// - Background: the window under every screen but the scene, and the sidebar's surfaces.
///   Its lightness decides light or dark system controls, and text is the built-in theme's
///   text, or black or white where that does not read. Cards are a shade lighter, never so
///   light that text on them stops reading.
/// - Accent: buttons, the selection tint and the mark standing on the accent.
/// - Scene: Cover Flow and Albums. The scene, its floor and the bar under the slider are all
///   shades of this one color, so they meet without a seam; text on it is chosen the same
///   way as on the background.
///
/// Warning, destructive and success colors come from the built-in light or dark theme.
enum ThemeDerivation {
    /// Text must reach this ratio on its surface; secondary text and the scene's quieter
    /// line reach the lower one.
    static let textMinimum = 4.5
    static let secondaryMinimum = 3.2

    static func palette(accent: Color, background: Color, scene: Color) -> ThemePalette {
        let window = RGB(background), stage = RGB(scene)
        let windowIsDark = window.prefersLightText, sceneIsDark = stage.prefersLightText
        let windowBase: ThemePalette = windowIsDark ? .dark : .light
        let sceneBase: ThemePalette = sceneIsDark ? .dark : .light

        var palette = windowBase
        palette.bg = window.color
        palette.stage = window.color
        let text = readable(windowBase.fg, on: window)
        let card = card(on: window, under: text, lighter: windowIsDark ? 0.06 : 0.6)
        palette.card = card.color
        palette.fg = text
        palette.f2 = secondary(text, on: [window, card])
        palette.f3 = text.opacity(0.3)

        palette.accent = accent
        palette.sel = accent.opacity(windowIsDark ? 0.3 : 0.18)
        // White on the accent, as in the built-in themes, while it still shows.
        palette.onAccent = ThemeContrast.ratio(.white, on: accent) >= ThemeContrast.onAccentMinimum
            ? .white : ThemePalette.light.fg

        palette.flowTop = stage.color
        palette.flowBottom = stage.mixed(with: sceneIsDark ? .white : .black, sceneIsDark ? 0.04 : 0.06).color
        palette.floorTop = stage.mixed(with: .black, sceneIsDark ? 0.3 : 0.1).color
        // The bar under the slider is drawn in `flowTop`; the floor ends in the same color.
        palette.floorBottom = stage.color
        palette.sceneText = readable(sceneBase.sceneText, on: stage)
        palette.sceneTextSoft = ThemeContrast.ratio(sceneBase.sceneTextSoft, on: stage.color) >= secondaryMinimum
            ? sceneBase.sceneTextSoft : palette.sceneText
        palette.sliderKnob = sceneBase.sliderKnob
        palette.sceneShade = stage.color
        palette.sceneShadow = sceneBase.sceneShadow
        return palette
    }

    /// The preferred color when it reads on the surface, else black or white, whichever
    /// reads better. One of the two always reaches 4.5:1.
    private static func readable(_ preferred: Color, on surface: RGB) -> Color {
        if ThemeContrast.ratio(preferred, on: surface.color) >= textMinimum { return preferred }
        return surface.prefersLightText ? .white : .black
    }

    /// The window lightened toward white as the built-in themes do, less where text on it
    /// would read below 4.5:1. With no lightening the card is the window, where text reads.
    private static func card(on window: RGB, under text: Color, lighter amount: Double) -> RGB {
        var amount = amount
        while amount > 0, ThemeContrast.ratio(text, on: window.mixed(with: .white, amount).color) < textMinimum {
            amount = max(0, amount - 0.01)
        }
        return window.mixed(with: .white, amount)
    }

    /// The text color, as transparent as the built-in themes make it while it still reads
    /// on every surface given.
    private static func secondary(_ text: Color, on surfaces: [RGB]) -> Color {
        var opacity = 0.6
        while opacity < 1, surfaces.contains(where: {
            ThemeContrast.ratio(text.opacity(opacity), on: $0.color) < secondaryMinimum
        }) {
            opacity += 0.05
        }
        return text.opacity(min(opacity, 1))
    }
}

/// An opaque sRGB color that can be mixed with another.
private struct RGB {
    var r, g, b: Double

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(r: Double(resolved.red), g: Double(resolved.green), b: Double(resolved.blue))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// White text reads at least as well as black on this color.
    var prefersLightText: Bool {
        ThemeContrast.ratio(.white, on: color) >= ThemeContrast.ratio(.black, on: color)
    }

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }
}
