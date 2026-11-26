import SwiftUI
import ClickwillShared

/// The colors Vice is made of, shared by its palette and its sunset so the two never drift
/// apart.
enum ViceColors {
    /// The window, the sidebar and every list.
    static let night = Color(red: 0x1b/255, green: 0x1a/255, blue: 0x38/255)
    static let pink = Color(red: 0xf0/255, green: 0x60/255, blue: 0x9e/255)

    /// The sky, from the top down: indigo, lavender, mauve, a light rose, then the rose
    /// horizon. The horizon is dark enough for the slider's white knob.
    static let indigo = hex(0x4F4A9E)
    static let lavender = hex(0x7B5DA8)
    static let mauve = hex(0xA46AA8)
    static let blush = hex(0xD27F96)
    static let horizon = hex(0xCC6A8A)
    /// The floor: rose water under the horizon, then plum, the color of the bar under the
    /// slider, so the scene meets it without a seam.
    static let water = hex(0xB4587E)
    static let plum = hex(0x6A3A78)

    /// Palms close by, and palms further off, paler in the haze.
    static let nearPalm = hex(0x5C2D5A)
    static let farPalm = hex(0x8C6CA8)

    private static func hex(_ value: UInt32) -> Color {
        Color(red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255,
              blue: Double(value & 0xff) / 255)
    }
}

public extension ThemePalette {
    /// Vice: a night-blue window with a hot pink accent, and Cover Flow at sunset among
    /// palms. The scene itself is painted by `SunsetBackdrop`; these scene colors are its
    /// outline, for the tile in Settings and for the contrast checks.
    static let vice = ThemePalette(
        colorScheme: .dark,
        bg: ViceColors.night,
        card: Color(red: 0x28/255, green: 0x26/255, blue: 0x50/255),
        stage: ViceColors.night,
        fg: Color(red: 0xf7/255, green: 0xf2/255, blue: 0xfa/255),
        f2: Color(red: 235/255, green: 225/255, blue: 245/255).opacity(0.62),
        f3: Color(red: 235/255, green: 225/255, blue: 245/255).opacity(0.3),
        sep: Color.white.opacity(0.1),
        sel: ViceColors.pink.opacity(0.3),
        glassBorder: Color.white.opacity(0.14),
        row: Color.white.opacity(0.04),
        rowHover: Color.white.opacity(0.07),
        trackHover: Color.white.opacity(0.08),
        field: Color.white.opacity(0.09),
        fieldBorder: Color.white.opacity(0.17),
        accent: ViceColors.pink,
        onAccent: .white,
        warn: ThemePalette.dark.warn,
        destructive: ThemePalette.dark.destructive,
        ok: ThemePalette.dark.ok,
        flowTop: ViceColors.plum,
        flowBottom: ViceColors.horizon,
        floorTop: ViceColors.water,
        floorBottom: ViceColors.plum,
        sceneText: .white,
        sceneTextSoft: Color(white: 0.92),
        sliderKnob: Color.white.opacity(0.94),
        sceneShade: Color(red: 0x12/255, green: 0x0f/255, blue: 0x26/255),
        sceneShadow: .black)
}

extension SceneBackdrop {
    /// The Vice theme's moving sunset; see `SunsetBackdrop`.
    static let sunset = SceneBackdrop(name: "sunset") { horizon, strength in
        AnyView(SunsetBackdrop(horizon: horizon, strength: strength))
    }
}
