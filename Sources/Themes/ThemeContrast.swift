import SwiftUI
import ClickwillShared

/// How readable a palette is, measured as drawn: a transparent color laid over the
/// surface under it. The editor shows the warnings; saving is never blocked.
public enum ThemeContrast {
    public struct Warning: Sendable, Equatable, Identifiable {
        public let message: String
        public var id: String { message }
    }

    /// Plain words, no ratios: the editor shows these to people choosing colors, not
    /// measuring them.
    public static func warnings(_ palette: ThemePalette) -> [Warning] {
        var warnings: [Warning] = []
        func check(_ color: Color, on surface: Color, below minimum: Double, _ message: String) {
            if ratio(color, on: surface) < minimum { warnings.append(Warning(message: message)) }
        }
        check(palette.fg, on: palette.bg, below: 4.5,
              "Text is hard to read on this background.")
        check(palette.f2, on: palette.bg, below: 3.2,
              "Song details and other quieter text are hard to read on this background.")
        check(palette.accent, on: palette.bg, below: 3,
              "The accent is hard to see on the background, so buttons and the selected album fade. I'd pick one that stands out more.")
        check(palette.onAccent, on: palette.accent, below: onAccentMinimum,
              "The badge on artwork is hard to see on this accent.")
        check(palette.sceneText, on: palette.flowTop, below: 4.5,
              "Album titles are hard to read on the Cover Flow color.")
        check(palette.sliderKnob, on: palette.flowBottom, below: 3,
              "The slider knob is hard to see on the Cover Flow color.")
        return warnings
    }

    /// The white clock on the dark theme's accent measures about 2.8:1 and is the design;
    /// below this a badge really disappears.
    static let onAccentMinimum = 2.5

    /// WCAG contrast ratio in sRGB, with `color` composited over `surface`.
    public static func ratio(_ color: Color, on surface: Color) -> Double {
        let top = rgba(color), under = rgba(surface)
        let a = top.3
        let drawn = (top.0 * a + under.0 * (1 - a), top.1 * a + under.1 * (1 - a), top.2 * a + under.2 * (1 - a))
        let l1 = luminance(drawn), l2 = luminance((under.0, under.1, under.2))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static func rgba(_ color: Color) -> (Double, Double, Double, Double) {
        let r = color.resolve(in: EnvironmentValues())
        return (Double(r.red), Double(r.green), Double(r.blue), Double(r.opacity))
    }

    private static func luminance(_ c: (Double, Double, Double)) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.0) + 0.7152 * linear(c.1) + 0.0722 * linear(c.2)
    }
}
