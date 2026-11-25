import SwiftUI

/// A theme's own picture over the scene's colors in Cover Flow and Albums, under the
/// artwork. Most themes have none; a theme that has one draws it here, so the scenes know
/// only this socket and never the theme behind it.
public struct SceneBackdrop: Sendable, Equatable {
    /// Two backdrops with the same name are the same picture.
    public let name: String
    private let draw: @MainActor @Sendable (_ horizon: CGFloat, _ strength: Double) -> AnyView

    /// - Parameter draw: the picture for a scene whose horizon lies at `horizon` (a share
    ///   of its height, 1 being the bottom edge), at `strength` (0 to 1) of its full light.
    public init(name: String,
                draw: @escaping @MainActor @Sendable (_ horizon: CGFloat, _ strength: Double) -> AnyView) {
        self.name = name
        self.draw = draw
    }

    @MainActor func view(horizon: CGFloat, strength: Double) -> AnyView {
        draw(horizon, strength)
    }

    public static func == (lhs: SceneBackdrop, rhs: SceneBackdrop) -> Bool {
        lhs.name == rhs.name
    }
}

/// The theme's backdrop for one scene, or nothing. It never takes clicks and is hidden from
/// VoiceOver: it is decoration.
public struct SceneBackdropLayer: View {
    @Environment(\.appTheme) private var theme
    private let horizon: CGFloat
    private let strength: Double

    /// - Parameters:
    ///   - horizon: where the floor begins, as a share of the scene's height.
    ///   - strength: Albums, with titles anywhere on the scene, show it fainter than
    ///     Cover Flow.
    public init(horizon: CGFloat, strength: Double = 1) {
        self.horizon = horizon
        self.strength = strength
    }

    public var body: some View {
        if let backdrop = theme.sceneBackdrop {
            backdrop.view(horizon: horizon, strength: strength)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
