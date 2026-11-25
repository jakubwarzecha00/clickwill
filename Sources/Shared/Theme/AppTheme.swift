import SwiftUI

/// What a theme decides for a window: its colors, and for some themes a moving picture
/// behind the scene. The typeface and the text sizes are not part of a theme - they are the
/// same in every one.
///
/// This is the socket the views use. Choosing a theme belongs to the themes module, which
/// the app plugs in in one place; without it every window has `standard`.
public struct AppTheme: Sendable, Equatable {
    public var palette: ThemePalette
    /// Drawn over the scene's colors in Cover Flow and Albums; nil for most themes.
    public var sceneBackdrop: SceneBackdrop?

    public init(palette: ThemePalette, sceneBackdrop: SceneBackdrop? = nil) {
        self.palette = palette
        self.sceneBackdrop = sceneBackdrop
    }

    /// The look with no theme chosen: dark.
    public static let standard = AppTheme(palette: .dark)
}

public extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .standard
}

public extension View {
    /// The root of a window: its theme for every view inside, and the light or dark
    /// appearance of system controls that goes with it.
    func themed(_ theme: AppTheme) -> some View {
        environment(\.appTheme, theme)
            .preferredColorScheme(theme.palette.colorScheme)
    }
}
