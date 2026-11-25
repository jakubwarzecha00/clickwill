import SwiftUI
import ClickwillShared

/// One color of a palette as the theme file and the editor know it: its key in the file,
/// its name in the editor and its group.
public struct ThemeToken: Sendable, Identifiable {
    public let key: String
    public let title: String
    /// Fixed per color, not taken from its current value: a color that is transparent in
    /// the design keeps its opacity slider after an opaque color is picked.
    public let allowsOpacity: Bool
    public let keyPath: WritableKeyPath<ThemePalette, Color> & Sendable

    public var id: String { key }

    init(_ key: String, _ title: String, opacity: Bool = false, _ keyPath: WritableKeyPath<ThemePalette, Color> & Sendable) {
        self.key = key
        self.title = title
        self.allowsOpacity = opacity
        self.keyPath = keyPath
    }

    /// A group of colors in the editor.
    public struct Group: Sendable, Identifiable {
        public let title: String
        public let tokens: [ThemeToken]
        public var id: String { title }
    }

    public static let groups: [Group] = [
        Group(title: "Surfaces", tokens: [
            ThemeToken("bg", "Background", \.bg),
            ThemeToken("card", "Card", \.card),
        ]),
        Group(title: "Text", tokens: [
            ThemeToken("fg", "Text", \.fg),
            ThemeToken("f2", "Secondary Text", opacity: true, \.f2),
            ThemeToken("f3", "Tertiary Text", opacity: true, \.f3),
        ]),
        Group(title: "Lines and Fills", tokens: [
            ThemeToken("sep", "Separator", opacity: true, \.sep),
            ThemeToken("sel", "Selection", opacity: true, \.sel),
            ThemeToken("glassBorder", "Glass Border", opacity: true, \.glassBorder),
            ThemeToken("row", "Row", opacity: true, \.row),
            ThemeToken("rowHover", "Row Hover", opacity: true, \.rowHover),
            ThemeToken("trackHover", "Song Hover", opacity: true, \.trackHover),
            ThemeToken("field", "Field", opacity: true, \.field),
            ThemeToken("fieldBorder", "Field Border", opacity: true, \.fieldBorder),
        ]),
        Group(title: "States", tokens: [
            ThemeToken("accent", "Accent", \.accent),
            ThemeToken("onAccent", "Mark on Accent", \.onAccent),
            ThemeToken("warn", "Warning", \.warn),
            ThemeToken("destructive", "Destructive", \.destructive),
            ThemeToken("ok", "Success", \.ok),
        ]),
        Group(title: "Cover Flow and Albums", tokens: [
            ThemeToken("flowTop", "Scene Top", \.flowTop),
            ThemeToken("flowBottom", "Scene Bottom", \.flowBottom),
            ThemeToken("floorTop", "Floor Top", \.floorTop),
            ThemeToken("floorBottom", "Floor Bottom", \.floorBottom),
            ThemeToken("sceneText", "Scene Text", \.sceneText),
            ThemeToken("sceneTextSoft", "Scene Secondary Text", \.sceneTextSoft),
            ThemeToken("sliderKnob", "Slider Knob", \.sliderKnob),
            // The fade's strength is set where it is drawn; the color itself is opaque.
            ThemeToken("sceneShade", "Cover Fade", \.sceneShade),
            ThemeToken("sceneShadow", "Cover Shadow", opacity: true, \.sceneShadow),
        ]),
    ]

    public static let all: [ThemeToken] = groups.flatMap(\.tokens)

    public static func named(_ key: String) -> ThemeToken? {
        all.first { $0.key == key }
    }
}
