import SwiftUI
import ClickwillShared

public extension ThemePalette {
    /// Vice: a night-blue window with a hot pink accent, and Cover Flow at sunset. The scene
    /// itself is painted by `SunsetBackdrop`; these scene colors are its outline, for the
    /// tile in Settings and for the contrast checks: the sky runs from night blue to magenta,
    /// the floor from rose back to night blue, so the bar under the slider meets it without
    /// a seam.
    static let vice = ThemePalette(
        colorScheme: .dark,
        bg: night,
        card: Color(red: 0x28/255, green: 0x26/255, blue: 0x50/255),
        stage: night,
        fg: Color(red: 0xf7/255, green: 0xf2/255, blue: 0xfa/255),
        f2: Color(red: 235/255, green: 225/255, blue: 245/255).opacity(0.62),
        f3: Color(red: 235/255, green: 225/255, blue: 245/255).opacity(0.3),
        sep: Color.white.opacity(0.1),
        sel: pink.opacity(0.3),
        glassBorder: Color.white.opacity(0.14),
        row: Color.white.opacity(0.04),
        rowHover: Color.white.opacity(0.07),
        trackHover: Color.white.opacity(0.08),
        field: Color.white.opacity(0.09),
        fieldBorder: Color.white.opacity(0.17),
        accent: pink,
        onAccent: .white,
        warn: ThemePalette.dark.warn,
        destructive: ThemePalette.dark.destructive,
        ok: ThemePalette.dark.ok,
        flowTop: night,
        flowBottom: Color(red: 0xb0/255, green: 0x4c/255, blue: 0x92/255),
        floorTop: Color(red: 0xb8/255, green: 0x5a/255, blue: 0x6a/255),
        floorBottom: night,
        sceneText: .white,
        sceneTextSoft: Color(white: 0.92),
        sliderKnob: Color.white.opacity(0.94),
        sceneShade: Color(red: 0x12/255, green: 0x0f/255, blue: 0x26/255),
        sceneShadow: .black)

    private static let night = Color(red: 0x1b/255, green: 0x1a/255, blue: 0x38/255)
    private static let pink = Color(red: 0xf0/255, green: 0x60/255, blue: 0x9e/255)
}

extension SceneBackdrop {
    /// The Vice theme's moving light; see `SunsetBackdrop`.
    static let sunset = SceneBackdrop(name: "sunset") { horizon, strength in
        AnyView(SunsetBackdrop(horizon: horizon, strength: strength))
    }
}
