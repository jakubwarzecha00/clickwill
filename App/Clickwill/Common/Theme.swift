import SwiftUI
import AppKit

/// Colors and dimensions from the UI design (dark theme).
/// Kept in one place, so the views do not repeat literals.
enum Theme {
    static let bg = Color(red: 0x1c/255, green: 0x1c/255, blue: 0x1e/255)
    static let card = Color(red: 0x2a/255, green: 0x2a/255, blue: 0x2c/255)
    static let fg = Color(red: 0xf5/255, green: 0xf5/255, blue: 0xf7/255)
    static let f2 = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.6)
    static let f3 = Color(red: 235/255, green: 235/255, blue: 245/255).opacity(0.3)
    static let sep = Color.white.opacity(0.09)
    static let sel = Color(red: 120/255, green: 145/255, blue: 180/255).opacity(0.3)
    static let glassBorder = Color.white.opacity(0.14)
    static let row = Color.white.opacity(0.04)
    static let rowHover = Color.white.opacity(0.07)
    /// A field to fill in. Separate from `row`: at 4% it blended with the panel background
    /// and it was not visible where one could type, and raising `row` would also brighten
    /// all list rows.
    static let field = Color.white.opacity(0.09)
    static let fieldBorder = Color.white.opacity(0.17)
    static let accent = Color(red: 0x7d/255, green: 0x9d/255, blue: 0xc4/255)
    static let warn = Color(red: 0xff/255, green: 0x9f/255, blue: 0x0a/255)
    static let destructive = Color(red: 0xff/255, green: 0x45/255, blue: 0x3a/255)
    static let ok = Color(red: 0x30/255, green: 0xd1/255, blue: 0x58/255)

    /// The position slider fill on the black scene (Cover Flow, Albums).
    /// The full accent shone brighter than the artwork the slider only scrolls through.
    static let positionSliderTint = accent.opacity(0.42)

    static let flowTop = Color(red: 0x0b/255, green: 0x0b/255, blue: 0x0d/255)
    static let flowBottom = Color(red: 0x16/255, green: 0x16/255, blue: 0x18/255)
    static let floorTop = Color(red: 0x08/255, green: 0x08/255, blue: 0x0a/255)
    static let floorBottom = Color(red: 0x0d/255, green: 0x0d/255, blue: 0x10/255)

    /// The shared scene background - the same one Cover Flow stands on. The toolbar
    /// and the playback bar no longer paint their own gray panels, but
    /// float over this background.
    static let stage = flowTop

    /// One grid for the whole side panel: the device card, the navigation rows
    /// and the section headers are computed from the same numbers, otherwise
    /// each element starts in a different place.
    static let panelInset: CGFloat = 12
    static let rowInset: CGFloat = 9
    static let rowIconWidth: CGFloat = 15
    static let rowIconGap: CGFloat = 9
    /// The icon column - the section headers start from it.
    static var panelIconColumn: CGFloat { panelInset + rowInset }
    static let toolbarHeight: CGFloat = 52
    static let playerBarHeight: CGFloat = 64
    /// The playback bar is a panel, not a strip - it does not stretch across the whole window.
    static let playerBarWidth: CGFloat = 900
    static let inspectorWidth: CGFloat = 282
    /// A screen change: the old one fades out completely, only then the new one lights up.
    /// With a plain crossfade both are semi-transparent for a moment and
    /// show through each other - that looks like flicker, not like a transition.
    static let screenFadeStep = 0.22
    static let screenFade: Animation = .linear(duration: screenFadeStep * 2)
    /// Computed on every use: `AnyTransition` is not `Sendable`,
    /// so it cannot be a global constant under strict concurrency.
    static var screenTransition: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.easeIn(duration: screenFadeStep).delay(screenFadeStep)),
                    removal: .opacity.animation(.easeOut(duration: screenFadeStep)))
    }

    /// The fixed width of the sidebar (0.3.1: no hiding and no dragging).
    static let sidebarWidth: CGFloat = 236

    /// The radius of large panels - the album scene, the inspector, the playback bar.
    static let panelCorner: CGFloat = 18

    /// The window's text scale, in points. Cover Flow, the album and the lists have a denser
    /// layout than the system styles, so the steps are here, and the views take them by
    /// name (`.font(.theme(.body))`). A symbol standing in line with text takes
    /// that text's step.
    enum TextSize: CGFloat {
        /// Fine print: "Read-only" on the iPod card, group headers in reordering.
        case fine = 10
        /// Counters and the labels next to them: free space, the time in the playback bar, "compilation".
        case small = 10.5
        /// Column headers, descriptions under a row, badges in a row.
        case caption = 11
        /// Captions under a title, the second line of a row, the counter in Cover Flow.
        case footnote = 11.5
        /// The artist in a row, group headers, helper buttons.
        case callout = 12
        /// Window text: descriptions, buttons, numbers in track rows.
        case body = 12.5
        /// The title in a list row, the iPod name on the card.
        case row = 13
        /// The title in a row of larger lists (reordering, an album from the queue).
        case rowLarge = 13.5
        /// Section headers in About.
        case heading = 14
        /// The album title under Cover Flow.
        case title3 = 15
        /// The artist under the album title.
        case title2 = 17
        /// The app name in About.
        case title = 20
        /// The album title on its screen.
        case largeTitle = 34
    }

    /// Symbols standing alone, not in line with text.
    enum SymbolSize: CGFloat {
        /// The iPod chooser arrow on the device card.
        case tiny = 8.5
        /// Arrows in rows and the exclamation mark on the artwork badge.
        case small = 9
        /// The clock on the badge of artwork waiting to be written.
        case badge = 10
        /// Previous/next buttons, adding artwork in the sheet.
        case medium = 15
        /// Play and pause.
        case large = 17
        /// Icons on the welcome page.
        case xLarge = 26
        /// The icon in About.
        case hero = 30
        /// The placeholder for an album without artwork.
        case placeholder = 40
        /// The placeholder for a disc without artwork.
        case placeholderLarge = 44
    }
}

extension Font {
    /// A step of the window's text scale (`Theme.TextSize`).
    static func theme(_ size: Theme.TextSize, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: size.rawValue, weight: weight, design: design)
    }

    /// A symbol standing alone (`Theme.SymbolSize`).
    static func symbol(_ size: Theme.SymbolSize, weight: Font.Weight? = nil) -> Font {
        .system(size: size.rawValue, weight: weight)
    }
}

extension View {
    /// A floating element with Liquid Glass. It paints no background of its own - it refracts
    /// what is under it - which is why buttons can stand directly on the scene,
    /// with no bar underneath.
    ///
    /// On macOS 14-25 the chip has no background of its own: the button gets the
    /// system style there (`chipButton`, `chipMenu`), and a label - `hintChip`. Every
    /// use of a chip goes together with one of them.
    @ViewBuilder func liquidChip(selected: Bool = false, height: CGFloat = 28, padding: CGFloat = 12) -> some View {
        if #available(macOS 26, *) {
            self
                .padding(.horizontal, padding)
                .frame(height: height)
                .glassSurface(tint: selected ? Theme.accent.opacity(0.3) : nil, interactive: true,
                              in: .rect(cornerRadius: height / 2))
        } else {
            self
        }
    }

    func glassChip(selected: Bool = false) -> some View {
        liquidChip(selected: selected, height: 26, padding: 10)
    }

    /// A larger floating panel - whole groups of controls fit in it,
    /// like the playback bar in Music.
    func liquidPanel(cornerRadius: CGFloat = 17) -> some View {
        glassSurface(in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// A sheet takes the keyboard the moment it appears (`SheetKeyFocus`).
    @ViewBuilder func sheetKeyFocus() -> some View {
        background(SheetKeyFocus())
    }
}

/// A sheet takes the keyboard the moment it appears.
///
/// Without this, a sheet opened right after a file choose panel sometimes did not become
/// the key window: Tab and space then moved through the buttons of the side panel
/// under the sheet, and the arrows scrolled Cover Flow in the background. Every
/// sheet in the app calls `sheetKeyFocus()`.
private struct SheetKeyFocus: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { KeyTakingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyTakingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.isSheet else { return }
            // After the current run loop pass - the sheet's window is on screen by then.
            DispatchQueue.main.async { window.makeKey() }
        }
    }
}

/// Liquid Glass exists from macOS 26, and Clickwill runs from macOS 14 since 0.3.0.
/// All floating elements go through these functions: on 26 and newer, glass
/// as before; on 14-25, a material with the same shape and the same tint,
/// with a thin outline in place of the glass edge.
extension View {
    @ViewBuilder func glassSurface<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint) }
                }
            }
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        }
    }

    @available(macOS 26, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// The main button of the toolbar and the disc screen: glass on 26+,
    /// system, filled with the accent, on older ones.
    @ViewBuilder func prominentGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    /// A scene reaching under the sidebar (macOS 26+). On older ones the bars have
    /// their own background, so a plain scene is enough.
    @ViewBuilder func backgroundExtension() -> some View {
        if #available(macOS 26, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }

    /// A button with a chip (`liquidChip`/`glassChip` on the label): on 26+ a plain
    /// button, the chip glass gives the background; on 14-25 a system button - the selected one
    /// filled with the accent, the others bordered.
    @ViewBuilder func chipButton(selected: Bool, small: Bool = false) -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.plain)
        } else if selected {
            buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(small ? .regular : .large).tint(Theme.accent)
        } else {
            buttonStyle(.bordered).buttonBorderShape(.capsule)
                .controlSize(small ? .regular : .large)
        }
    }

    /// A menu with a chip on the label - like `chipButton`, for `Menu`.
    @ViewBuilder func chipMenu() -> some View {
        if #available(macOS 26, *) {
            menuStyle(.borderlessButton)
        } else {
            menuStyle(.button).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        }
    }

    /// A label in a chip (not a button), e.g. the hint when dropping files:
    /// glass on 26+, the standard material with an outline on 14-25.
    @ViewBuilder func hintChip() -> some View {
        if #available(macOS 26, *) {
            glassChip(selected: true)
        } else {
            padding(.horizontal, 10).frame(height: 26)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        }
    }
}
