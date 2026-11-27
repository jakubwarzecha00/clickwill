import SwiftUI

/// A theme's own picture behind the scenes of Cover Flow and Albums. Most themes have none;
/// a theme that has one draws it here, so the app knows only this socket and never the
/// theme behind it.
///
/// The window draws the picture once, behind the whole page beside the sidebar: under the
/// toolbar, the slider and the player, and on macOS 26 and later, mirrored and blurred, under
/// the sidebar's glass. A scene only says where its horizon lies (`sceneBackdrop`) and leaves
/// out its own colors (`sceneColors`).
public struct SceneBackdrop: Sendable, Equatable {
    /// Two backdrops with the same name are the same picture.
    public let name: String
    private let draw: @MainActor @Sendable (_ horizon: CGFloat, _ strength: Double, _ moment: Int) -> AnyView

    /// - Parameter draw: the picture for a page whose horizon lies at `horizon` (a share
    ///   of its height, 1 being the bottom edge), at `strength` (0 to 1) of its full light.
    ///   `moment` names what the scene shows now; a picture that moves may react to its change.
    public init(name: String,
                draw: @escaping @MainActor @Sendable (_ horizon: CGFloat, _ strength: Double, _ moment: Int) -> AnyView) {
        self.name = name
        self.draw = draw
    }

    @MainActor func view(horizon: CGFloat, strength: Double, moment: Int) -> AnyView {
        draw(horizon, strength, moment)
    }

    public static func == (lhs: SceneBackdrop, rhs: SceneBackdrop) -> Bool {
        lhs.name == rhs.name
    }
}

/// What the scene on screen asks of the theme's picture.
struct ScenePlacement: Equatable {
    /// The scene; a change crossfades the picture.
    let id: String
    /// Where the floor begins; nil puts the horizon on the page's bottom edge.
    let horizon: Anchor<CGPoint>?
    let strength: Double
    let moment: Int
}

/// The scene on screen. While one page fades out and the next fades in, the one already
/// showing keeps the picture, and a page without a scene does not take it away.
struct SceneBackdropKey: PreferenceKey {
    static var defaultValue: ScenePlacement? { nil }

    static func reduce(value: inout ScenePlacement?, nextValue: () -> ScenePlacement?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    /// Asks the window for the theme's picture behind this scene, and lets it show through
    /// the toolbar as it does through the sidebar. Does nothing when the theme has none.
    /// - Parameters:
    ///   - id: names the scene; the picture crossfades when another scene takes over.
    ///   - horizon: where the floor begins, as a point of this view; nil puts it on the
    ///     page's bottom edge.
    ///   - strength: Albums, with titles anywhere on the scene, show it fainter than
    ///     Cover Flow.
    ///   - moment: the index of the album the scene shows now.
    public func sceneBackdrop(id: String, horizon: UnitPoint? = nil, strength: Double = 1, moment: Int) -> some View {
        modifier(SceneBackdropRequest(id: id, horizon: horizon, strength: strength, moment: moment))
    }

    /// The scene's own colors behind it, left out when the theme's picture is drawn behind
    /// the whole page instead.
    public func sceneColors<Colors: View>(@ViewBuilder _ colors: () -> Colors) -> some View {
        background { SceneColors(colors: colors()) }
    }
}

private struct SceneBackdropRequest: ViewModifier {
    @Environment(\.appTheme) private var theme
    let id: String
    let horizon: UnitPoint?
    let strength: Double
    let moment: Int

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: SceneBackdropKey.self, value: .unitPoint(horizon ?? .bottom)) { anchor in
                guard theme.sceneBackdrop != nil else { return nil }
                return ScenePlacement(id: id, horizon: horizon == nil ? nil : anchor, strength: strength, moment: moment)
            }
            // Over a page that does not scroll, the system lays its own dark background
            // under the toolbar, which would hide the picture there.
            .toolbarBackground(hidden: theme.sceneBackdrop != nil)
    }
}

private extension View {
    @ViewBuilder func toolbarBackground(hidden: Bool) -> some View {
        let visibility: Visibility = hidden ? .hidden : .automatic
        if #available(macOS 15, *) {
            toolbarBackgroundVisibility(visibility, for: .windowToolbar)
        } else {
            toolbarBackground(visibility, for: .windowToolbar)
        }
    }
}

private struct SceneColors<Colors: View>: View {
    @Environment(\.appTheme) private var theme
    let colors: Colors

    var body: some View {
        if theme.sceneBackdrop == nil { colors }
    }
}

extension View {
    /// The window's side: lays `base` behind this page, with the theme's picture for the
    /// scene on screen over it. Both reach under the toolbar and to the bottom edge, and on
    /// macOS 26 and later, mirrored and blurred, under the sidebar's glass.
    public func pageBackground<Base: View>(@ViewBuilder _ base: () -> Base) -> some View {
        let base = base()
        return backgroundPreferenceValue(SceneBackdropKey.self) { placement in
            ZStack {
                base
                SceneBackdropCanvas(placement: placement)
            }
            // Only up and down: the picture keeps the page's width, so its palms stay beside
            // the artwork, and the sidebar gets the mirror.
            .ignoresSafeArea(edges: .vertical)
            .backgroundExtension()
        }
    }
}

/// The picture across the whole page, measured in the same space as the horizon's anchor.
/// It never takes clicks and is hidden from VoiceOver: it is decoration.
private struct SceneBackdropCanvas: View {
    @Environment(\.appTheme) private var theme
    let placement: ScenePlacement?

    var body: some View {
        GeometryReader { geometry in
            if let placement, let backdrop = theme.sceneBackdrop {
                let horizon = placement.horizon.map { geometry[$0].y / max(geometry.size.height, 1) } ?? 1
                backdrop.view(horizon: horizon, strength: placement.strength, moment: placement.moment)
                    .id(placement.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: placement?.id)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
