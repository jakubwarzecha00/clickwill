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
        #expect(ThemeContrast.ratio(light.fg, on: light.bg) >= 7)
        #expect(ThemeContrast.ratio(light.accent, on: light.bg) >= 4.5)
        #expect(ThemeContrast.ratio(light.onAccent, on: light.accent) >= 4.5)
    }

    /// Secondary text keeps the system label transparency, like the text in system controls
    /// beside it. It reads as secondary, under the 4.5:1 of body text.
    @Test func secondaryTextKeepsTheSystemsContrast() {
        #expect(ThemeContrast.ratio(light.f2, on: light.bg) >= 3.2)
    }

    /// Tertiary text is for placeholders and empty states, with no reading threshold. The
    /// measured value is pinned, so a change to its transparency is a decision, not an accident.
    @Test func tertiaryTextIsPinned() {
        let ratio = ThemeContrast.ratio(light.f3, on: light.bg)
        #expect(abs(ratio - 1.71) < 0.05)
    }

    @Test func theSceneIsLightAndItsTextDark() {
        #expect(ThemeContrast.ratio(light.sceneText, on: light.flowTop) >= 7)
        #expect(ThemeContrast.ratio(light.sceneText, on: light.flowBottom) >= 7)
        #expect(ThemeContrast.ratio(light.sliderKnob, on: light.flowBottom) >= 7)
    }

    @Test func statesAreReadableAsText() {
        #expect(ThemeContrast.ratio(light.warn, on: light.bg) >= 4.5)
        #expect(ThemeContrast.ratio(light.destructive, on: light.bg) >= 4.5)
        #expect(ThemeContrast.ratio(light.ok, on: light.bg) >= 4.5)
    }
}
