import SwiftUI

/// One of the three colors a user picks for a theme: its key in the file and its name and
/// job in the editor. Every other color of the palette is worked out from these
/// (`ThemeDerivation`), so no combination of picks can leave text unreadable or the Cover
/// Flow scene in pieces.
public struct ThemeToken: Sendable, Identifiable, Equatable {
    public let key: String
    public let title: String
    /// Where the color shows, in one line under its name.
    public let detail: String

    public var id: String { key }

    public static let accent = ThemeToken(key: "accent", title: "Accent",
                                          detail: "Buttons, the selection and the slider.")
    public static let background = ThemeToken(key: "background", title: "Background",
                                              detail: "The window, the sidebar and every list.")
    public static let scene = ThemeToken(key: "scene", title: "Cover Flow",
                                         detail: "The scene behind the artwork in Cover Flow and Albums.")

    public static let all: [ThemeToken] = [accent, background, scene]

    public static func named(_ key: String) -> ThemeToken? {
        all.first { $0.key == key }
    }
}
