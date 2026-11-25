import SwiftUI
import ClickwillShared

public extension ThemePalette {
    /// The light look. Cover Flow and Albums stand on a light scene too.
    ///
    /// Secondary and tertiary text use the system label colors' transparency, so they read
    /// the same as text in system controls next to them.
    static let light = ThemePalette(
        colorScheme: .light,
        bg: Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255),
        card: .white,
        fg: Color(red: 0x1d/255, green: 0x1d/255, blue: 0x1f/255),
        f2: Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6),
        f3: Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.3),
        sep: Color.black.opacity(0.1),
        sel: Color(red: 0x2f/255, green: 0x6a/255, blue: 0xa8/255).opacity(0.18),
        glassBorder: Color.black.opacity(0.1),
        row: Color.black.opacity(0.03),
        rowHover: Color.black.opacity(0.05),
        trackHover: Color.black.opacity(0.06),
        field: Color.black.opacity(0.05),
        fieldBorder: Color.black.opacity(0.16),
        accent: Color(red: 0x2f/255, green: 0x6a/255, blue: 0xa8/255),
        onAccent: .white,
        warn: Color(red: 0xb2/255, green: 0x50/255, blue: 0x00/255),
        destructive: Color(red: 0xd7/255, green: 0x00/255, blue: 0x15/255),
        ok: Color(red: 0x1f/255, green: 0x7d/255, blue: 0x36/255),
        flowTop: Color(red: 0xf2/255, green: 0xf2/255, blue: 0xf4/255),
        flowBottom: Color(red: 0xe4/255, green: 0xe4/255, blue: 0xe8/255),
        floorTop: Color(red: 0xda/255, green: 0xda/255, blue: 0xde/255),
        floorBottom: Color(red: 0xe6/255, green: 0xe6/255, blue: 0xea/255),
        sceneText: Color(red: 0x1d/255, green: 0x1d/255, blue: 0x1f/255),
        sceneTextSoft: Color(white: 0.25),
        // A white knob disappears on the light track; the text color stands out.
        sliderKnob: Color(red: 0x1d/255, green: 0x1d/255, blue: 0x1f/255),
        sceneShade: Color(white: 0.96),
        sceneShadow: Color.black.opacity(0.55))
}
