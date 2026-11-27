import SwiftUI
import Testing
import ClickwillShared
@testable import ClickwillThemes

struct ThemeDerivationTests {
    /// Grays, saturated hues and the colors between, light to dark.
    private static let samples: [Color] = {
        var colors: [Color] = []
        for level in stride(from: 0.0, through: 1.0, by: 0.125) {
            colors.append(Color(.sRGB, red: level, green: level, blue: level))
        }
        for hue in stride(from: 0.0, to: 1.0, by: 1.0 / 12) {
            for (saturation, brightness) in [(1.0, 1.0), (1.0, 0.6), (0.5, 0.85), (0.8, 0.3)] {
                colors.append(Color(hue: hue, saturation: saturation, brightness: brightness))
            }
        }
        return colors
    }()

    private func palette(accent: Color = Color(white: 0.5), background: Color, scene: Color) -> ThemePalette {
        ThemeDerivation.palette(accent: accent, background: background, scene: scene)
    }

    /// Whatever the user picks, the only warning left is an accent that fades into the
    /// background, which is a choice the user can see and keep.
    @Test func everyPickReadsClearlyExceptMaybeTheAccent() {
        for background in Self.samples {
            for scene in Self.samples.prefix(9) + [Color(.sRGB, red: 0.78, green: 0.04, blue: 0.96)] {
                for accent in [Color.white, .black, Color(hue: 0.6, saturation: 1, brightness: 1)] {
                    let palette = palette(accent: accent, background: background, scene: scene)
                    let warnings = ThemeContrast.warnings(palette).filter { !$0.message.hasPrefix("The accent") }
                    #expect(warnings.isEmpty, "\(HexColor.string(background)) \(HexColor.string(scene)): \(warnings)")
                }
            }
        }
    }

    /// Every gray the color well can give, so a narrow band where text and the lighter card
    /// stop reading cannot slip between samples.
    @Test func textReadsOnTheWindowAndOnCardsForEveryGray() {
        for level in 0...255 {
            let gray = Color(.sRGB, red: Double(level) / 255, green: Double(level) / 255, blue: Double(level) / 255)
            let palette = palette(background: gray, scene: gray)
            let name = HexColor.string(gray)
            #expect(ThemeContrast.ratio(palette.fg, on: palette.stage) >= 4.5, "fg on stage \(name)")
            #expect(ThemeContrast.ratio(palette.fg, on: palette.card) >= 4.5, "fg on card \(name)")
            #expect(ThemeContrast.ratio(palette.f2, on: palette.bg) >= 3.2, "f2 on bg \(name)")
            #expect(ThemeContrast.ratio(palette.f2, on: palette.card) >= 3.2, "f2 on card \(name)")
            #expect(ThemeContrast.ratio(palette.sceneText, on: palette.flowTop) >= 4.5, "scene text \(name)")
        }
    }

    /// The Background color paints the window under every screen but the scene.
    @Test func theBackgroundPaintsTheWindow() {
        let teal = Color(.sRGB, red: 0.1, green: 0.4, blue: 0.45)
        let palette = palette(background: teal, scene: .black)
        #expect(HexColor.string(palette.stage) == HexColor.string(teal))
        #expect(HexColor.string(palette.bg) == HexColor.string(teal))
    }

    /// The scene, its floor and the bar under the slider are one color, so they meet
    /// without a seam.
    @Test func theFloorEndsInTheSceneColor() {
        let magenta = Color(.sRGB, red: 0.78, green: 0.04, blue: 0.96)
        let palette = palette(background: .black, scene: magenta)
        #expect(HexColor.string(palette.floorBottom) == HexColor.string(palette.flowTop))
        #expect(HexColor.string(palette.flowTop) == HexColor.string(magenta))
        #expect(HexColor.string(palette.sceneShade) == HexColor.string(magenta))
    }

    @Test func theBackgroundDecidesLightOrDarkControls() {
        #expect(palette(background: .white, scene: .black).colorScheme == .light)
        #expect(palette(background: Color(white: 0.1), scene: .white).colorScheme == .dark)
    }

    @Test func theStartingColorsLookLikeTheBuiltInThemes() {
        let dark = CustomTheme(name: "D", start: .dark).palette
        #expect(dark.colorScheme == .dark)
        #expect(HexColor.string(dark.bg) == HexColor.string(ThemePalette.dark.bg))
        #expect(HexColor.string(dark.fg) == HexColor.string(ThemePalette.dark.fg))
        #expect(HexColor.string(dark.onAccent) == HexColor.string(ThemePalette.dark.onAccent))
        let light = CustomTheme(name: "L", start: .light).palette
        #expect(light.colorScheme == .light)
        #expect(HexColor.string(light.fg) == HexColor.string(ThemePalette.light.fg))
        #expect(HexColor.string(light.warn) == HexColor.string(ThemePalette.light.warn))
    }
}
