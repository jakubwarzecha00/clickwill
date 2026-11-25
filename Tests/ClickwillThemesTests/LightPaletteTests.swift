import SwiftUI
import Testing
import ClickwillShared
@testable import ClickwillThemes

/// Contrast of the light palette, measured as drawn: a transparent color laid over the
/// surface under it.
struct LightPaletteTests {
    private let light = ThemePalette.light

    @Test func isLight() {
        #expect(light.colorScheme == .light)
    }

    @Test func textStandsOutOnTheWindow() {
        #expect(Contrast.ratio(light.fg, on: light.bg) >= 7)
        #expect(Contrast.ratio(light.accent, on: light.bg) >= 4.5)
        #expect(Contrast.ratio(light.onAccent, on: light.accent) >= 4.5)
    }

    /// Secondary text keeps the system label transparency, like the text in system controls
    /// beside it. It reads as secondary, under the 4.5:1 of body text.
    @Test func secondaryTextKeepsTheSystemsContrast() {
        #expect(Contrast.ratio(light.f2, on: light.bg) >= 3.2)
    }

    /// Tertiary text is for placeholders and empty states, with no reading threshold. The
    /// measured value is pinned, so a change to its transparency is a decision, not an accident.
    @Test func tertiaryTextIsPinned() {
        let ratio = Contrast.ratio(light.f3, on: light.bg)
        #expect(abs(ratio - 1.71) < 0.05)
    }

    @Test func theSceneIsLightAndItsTextDark() {
        #expect(Contrast.ratio(light.sceneText, on: light.flowTop) >= 7)
        #expect(Contrast.ratio(light.sceneText, on: light.flowBottom) >= 7)
        #expect(Contrast.ratio(light.sliderKnob, on: light.flowBottom) >= 7)
    }

    @Test func statesAreReadableAsText() {
        #expect(Contrast.ratio(light.warn, on: light.bg) >= 4.5)
        #expect(Contrast.ratio(light.destructive, on: light.bg) >= 4.5)
        #expect(Contrast.ratio(light.ok, on: light.bg) >= 4.5)
    }
}

/// WCAG contrast ratio in sRGB.
enum Contrast {
    static func ratio(_ color: Color, on surface: Color) -> Double {
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
