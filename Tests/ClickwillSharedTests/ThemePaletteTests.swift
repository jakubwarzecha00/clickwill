import Testing
import SwiftUI
@testable import ClickwillShared

struct ThemePaletteTests {
    private func resolved(_ color: Color) -> Color.Resolved { color.resolve(in: EnvironmentValues()) }

    private func resolved(_ color: ThemeColor, in theme: AppTheme = .standard) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.appTheme = theme
        return color.resolve(in: environment)
    }

    /// The dark palette is the look from before themes: the same components and alpha.
    @Test func darkKeepsTheDesignValues() {
        let dark = ThemePalette.dark
        #expect(dark.colorScheme == .dark)
        #expect(resolved(dark.bg) == resolved(Color(red: 0x1c/255, green: 0x1c/255, blue: 0x1e/255)))
        #expect(resolved(dark.fg) == resolved(Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255)))
        #expect(resolved(dark.f2) == resolved(Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.6)))
        #expect(resolved(dark.accent) == resolved(Color(red: 0x7d/255, green: 0x9d/255, blue: 0xc4/255)))
        #expect(resolved(dark.sep) == resolved(Color.white.opacity(0.09)))
        #expect(resolved(dark.trackHover) == resolved(Color.white.opacity(0.08)))
        #expect(resolved(dark.sceneTextSoft) == resolved(Color(white: 0.92)))
        #expect(resolved(dark.sliderKnob) == resolved(Color.white.opacity(0.94)))
    }

    @Test func aThemeColorIsTakenFromTheWindowsTheme() {
        var other = AppTheme.standard
        other.palette.accent = .red
        #expect(resolved(Theme.accent) == resolved(ThemePalette.dark.accent))
        #expect(resolved(Theme.accent, in: other) == resolved(Color.red))
    }

    @Test func opacityFollowsThePalette() {
        var other = AppTheme.standard
        other.palette.accent = .red
        #expect(resolved(Theme.positionSliderTint) == resolved(ThemePalette.dark.accent.opacity(0.42)))
        #expect(resolved(Theme.positionSliderTint, in: other) == resolved(Color.red.opacity(0.42)))
        #expect(resolved(Theme.stage) == resolved(ThemePalette.dark.flowTop))
    }
}
