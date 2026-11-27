import SwiftUI

/// The system position slider for a list (Cover Flow, Albums): the value is
/// the item number, not a fraction. System, not drawn - the Liquid Glass knob
/// while dragging comes from macOS, just as in the playback bar.
public struct PositionSlider: View {
    @Binding public var index: Int
    public let count: Int
    public let label: String

    public init(index: Binding<Int>, count: Int, label: String) {
        _index = index
        self.count = count
        self.label = label
    }

    public var body: some View {
        Slider(value: Binding(get: { Double(index) },
                              set: { index = min(count - 1, max(0, Int($0.rounded()))) }),
               in: 0...Double(max(1, count - 1)))
            .themeTint(Theme.positionSliderTint)
            .disabled(count < 2)
            .accessibilityLabel(label)
            .accessibilityValue("\(index + 1) of \(count)")
    }
}

/// "4 of 18" next to the slider. It takes as much space as the longest label
/// ("18 of 18") - otherwise going from 9 to 10 widened the counter,
/// and the slider next to it shrank by a few points while scrolling.
public struct PositionCounter: View {
    public let index: Int
    public let count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    public var body: some View {
        ZStack(alignment: .trailing) {
            Text("\(count) of \(count)").hidden()
            Text("\(index + 1) of \(count)")
        }
        .font(.theme(.footnote)).foregroundStyle(Theme.sceneText.opacity(0.45)).monospacedDigit()
        .accessibilityHidden(true)
    }
}

/// A vertical position slider (the Albums wheel), looking like the system one: a thin
/// track, a fill from the top to the knob, a white knob, glass while dragging
/// (Liquid Glass). Custom, because there is no system vertical one: a vertical `NSSlider`
/// has its start at the bottom, and a rotated one is rotated only on screen,
/// it reads clicks unrotated (checked by recording a drag).
public struct VerticalPositionSlider: View {
    @Binding public var index: Int
    public let count: Int
    public let label: String

    public init(index: Binding<Int>, count: Int, label: String) {
        _index = index
        self.count = count
        self.label = label
    }
    @State private var dragging = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.appTheme) private var theme

    /// Knob and track dimensions of the slider under Cover Flow, rotated.
    private static let knob = CGSize(width: 15, height: 20)
    private static let track: CGFloat = 5

    public var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.height - Self.knob.height)
            let offset = count > 1 ? travel * CGFloat(index) / CGFloat(count - 1) : 0
            ZStack(alignment: .top) {
                Capsule().fill(Theme.sceneText.opacity(0.16)).frame(width: Self.track)
                Capsule().fill(Theme.positionSliderTint)
                    .frame(width: Self.track, height: offset + Self.knob.height / 2)
                knob
                    .frame(width: Self.knob.width, height: Self.knob.height)
                    .scaleEffect(dragging ? 1.4 : 1)
                    .animation(.spring(duration: 0.2, bounce: 0.3), value: dragging)
                    .offset(y: offset)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    guard enabled, count > 1 else { return }
                    dragging = true
                    let fraction = (drag.location.y - Self.knob.height / 2) / travel
                    index = min(count - 1, max(0, Int((fraction * CGFloat(count - 1)).rounded())))
                }
                .onEnded { _ in dragging = false })
        }
        .disabled(count < 2)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(index + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(count - 1, index + 1)
            case .decrement: index = max(0, index - 1)
            @unknown default: break
            }
        }
    }

    private var knobShadow: Color { Theme.sceneShadow.opacity(0.45).color(in: theme.palette) }

    @ViewBuilder private var knob: some View {
        if dragging {
            Capsule().fill(.clear).clearGlassKnob(shadow: knobShadow)
        } else {
            Capsule().fill(Theme.sliderKnob)
                .shadow(color: knobShadow, radius: 1.5, y: 1)
        }
    }
}

private extension View {
    /// The knob while dragging: a transparent lens (`.clear` glass)
    /// on macOS 26+. On 14-25 there is nothing to make a lens with - the knob keeps
    /// its color at rest and only grows.
    @ViewBuilder func clearGlassKnob(shadow: Color) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.clear, in: .capsule)
        } else {
            Capsule().fill(Theme.sliderKnob).shadow(color: shadow, radius: 1.5, y: 1)
        }
    }
}
