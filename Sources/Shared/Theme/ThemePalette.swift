import SwiftUI

/// Every color a theme decides, each named by its job in the window.
///
/// Views never read a palette directly: they name a color (`Theme.fg`), and the window's
/// theme (`AppTheme`) answers with the color from its palette.
public struct ThemePalette: Sendable, Equatable {
    /// Light or dark: system controls, menus and materials follow it.
    public var colorScheme: ColorScheme

    // Surfaces.
    public var bg: Color
    public var card: Color

    // Text on the window's surfaces.
    public var fg: Color
    public var f2: Color
    public var f3: Color

    // Lines and fills.
    public var sep: Color
    public var sel: Color
    public var glassBorder: Color
    public var row: Color
    public var rowHover: Color
    /// The hover under a track row in an album.
    public var trackHover: Color
    /// A field to fill in. Separate from `row`: at 4% it blended with the panel background
    /// and it was not visible where one could type, and raising `row` would also brighten
    /// all list rows.
    public var field: Color
    public var fieldBorder: Color

    // States.
    public var accent: Color
    /// A mark standing on the accent or on a state color, such as the badge on artwork.
    public var onAccent: Color
    public var warn: Color
    public var destructive: Color
    public var ok: Color

    // The scene Cover Flow and Albums stand on.
    public var flowTop: Color
    public var flowBottom: Color
    public var floorTop: Color
    public var floorBottom: Color
    /// Text and marks drawn on the scene: album titles, the jump letter, the slider.
    public var sceneText: Color
    /// The quieter line on the scene: the artist on the wheel, facts in the info column.
    public var sceneTextSoft: Color
    /// The knob of the position slider.
    public var sliderKnob: Color

    public init(colorScheme: ColorScheme, bg: Color, card: Color, fg: Color, f2: Color, f3: Color,
                sep: Color, sel: Color, glassBorder: Color, row: Color, rowHover: Color, trackHover: Color,
                field: Color, fieldBorder: Color, accent: Color, onAccent: Color, warn: Color,
                destructive: Color, ok: Color, flowTop: Color, flowBottom: Color, floorTop: Color,
                floorBottom: Color, sceneText: Color, sceneTextSoft: Color, sliderKnob: Color) {
        self.colorScheme = colorScheme
        self.bg = bg
        self.card = card
        self.fg = fg
        self.f2 = f2
        self.f3 = f3
        self.sep = sep
        self.sel = sel
        self.glassBorder = glassBorder
        self.row = row
        self.rowHover = rowHover
        self.trackHover = trackHover
        self.field = field
        self.fieldBorder = fieldBorder
        self.accent = accent
        self.onAccent = onAccent
        self.warn = warn
        self.destructive = destructive
        self.ok = ok
        self.flowTop = flowTop
        self.flowBottom = flowBottom
        self.floorTop = floorTop
        self.floorBottom = floorBottom
        self.sceneText = sceneText
        self.sceneTextSoft = sceneTextSoft
        self.sliderKnob = sliderKnob
    }
}

public extension ThemePalette {
    /// The dark look from the UI design.
    static let dark = ThemePalette(
        colorScheme: .dark,
        bg: Color(red: 0x1c/255, green: 0x1c/255, blue: 0x1e/255),
        card: Color(red: 0x2a/255, green: 0x2a/255, blue: 0x2c/255),
        fg: Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255),
        f2: Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.6),
        f3: Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.3),
        sep: Color.white.opacity(0.09),
        sel: Color(red: 120/255, green: 145/255, blue: 180/255).opacity(0.3),
        glassBorder: Color.white.opacity(0.14),
        row: Color.white.opacity(0.04),
        rowHover: Color.white.opacity(0.07),
        trackHover: Color.white.opacity(0.08),
        field: Color.white.opacity(0.09),
        fieldBorder: Color.white.opacity(0.17),
        accent: Color(red: 0x7d/255, green: 0x9d/255, blue: 0xc4/255),
        onAccent: .white,
        warn: Color(red: 0xff/255, green: 0x9f/255, blue: 0x0a/255),
        destructive: Color(red: 0xff/255, green: 0x45/255, blue: 0x3a/255),
        ok: Color(red: 0x30/255, green: 0xd1/255, blue: 0x58/255),
        flowTop: Color(red: 0x0b/255, green: 0x0b/255, blue: 0x0d/255),
        flowBottom: Color(red: 0x16/255, green: 0x16/255, blue: 0x18/255),
        floorTop: Color(red: 0x08/255, green: 0x08/255, blue: 0x0a/255),
        floorBottom: Color(red: 0x0d/255, green: 0x0d/255, blue: 0x10/255),
        sceneText: .white,
        sceneTextSoft: Color(white: 0.92),
        sliderKnob: Color.white.opacity(0.94))
}
