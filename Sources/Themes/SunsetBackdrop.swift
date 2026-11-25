import SwiftUI
import ClickwillShared

/// The Vice scene: a sunset painted in one unbroken gradient, from night at the top through
/// indigo, violet and magenta to a thin coral glow on the horizon, then back through violet
/// to night under the floor. Over it, from the bottom up:
///
/// - soft red and orange clouds drifting across the middle (soft light), and a violet haze
///   in the upper left;
/// - a low sun that slowly swells and fades on the horizon, and streaks of blue, pink and
///   violet light crossing it (screen, so they only add light);
/// - a faint violet shade in the lower right corner (multiply).
///
/// It covers the palette's own scene colors. It holds still while Reduce Motion is on or the
/// window is not in front, and redraws at most 30 times a second.
struct SunsetBackdrop: View {
    /// Where the floor begins, as a share of the height; 1 puts the horizon on the bottom edge.
    let horizon: CGFloat
    /// 0 to 1: below 1, night is laid over the picture and the light is fainter.
    let strength: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || activeState == .inactive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let size = geometry.size
                let line = horizon * size.height
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: Self.sky(horizon: horizon), startPoint: .top, endPoint: .bottom)
                    clouds(size: size, line: line, time: time)
                    haze(size: size, time: time)
                    ZStack(alignment: .topLeading) {
                        sun(width: size.width, time: time)
                            .position(x: size.width / 2, y: line)
                        ForEach(Self.streaks.indices, id: \.self) { index in
                            streak(Self.streaks[index], size: size, line: line, time: time)
                        }
                    }
                    .blendMode(.screen)
                    LinearGradient(colors: [.clear, Self.shade], startPoint: UnitPoint(x: 0.35, y: 0.2), endPoint: .bottomTrailing)
                        .blendMode(.multiply)
                        .opacity(0.3)
                    Self.night.opacity((1 - strength) * 0.8)
                }
                .compositingGroup()
            }
        }
        .clipped()
    }

    // MARK: The painting

    private static let night = Color(red: 0x1b/255, green: 0x1a/255, blue: 0x38/255)
    private static let shade = Color(red: 0x5b/255, green: 0x2a/255, blue: 0x86/255)

    /// Measured from a sunset sky: the stops above the horizon are shares of the sky, the
    /// ones below shares of the floor, so the coral stays a thin glow whatever the height.
    static func sky(horizon: CGFloat) -> [Gradient.Stop] {
        let h = min(max(horizon, 0.05), 1)
        func hex(_ value: UInt32) -> Color {
            Color(red: Double(value >> 16 & 0xff) / 255, green: Double(value >> 8 & 0xff) / 255,
                  blue: Double(value & 0xff) / 255)
        }
        return [
            .init(color: night, location: 0),
            .init(color: hex(0x4C3E73), location: h * 0.45),
            .init(color: hex(0x854788), location: h * 0.75),
            .init(color: hex(0xB04C92), location: h * 0.94),
            .init(color: hex(0xD96654), location: h),
            .init(color: hex(0x7E3D6E), location: h + (1 - h) * 0.35),
            .init(color: night, location: 1),
        ]
    }

    // MARK: Clouds and haze

    /// A blurred brush stroke of color: its height around the horizon as a share of the
    /// scene, its length and thickness as shares too, and how far and how slowly it sways.
    private struct Cloud {
        let color: Color
        let offset: CGFloat
        let length: CGFloat
        let thickness: CGFloat
        let blur: CGFloat
        let opacity: Double
        let period: Double
    }

    private static let clouds = [
        Cloud(color: Color(red: 1, green: 0.23, blue: 0.27), offset: -0.12, length: 0.95, thickness: 0.05,
              blur: 25, opacity: 0.55, period: 31),
        Cloud(color: Color(red: 1, green: 0.6, blue: 0.24), offset: -0.22, length: 0.6, thickness: 0.025,
              blur: 15, opacity: 0.6, period: 23),
        Cloud(color: Color(red: 1, green: 0.6, blue: 0.24), offset: -0.06, length: 0.7, thickness: 0.03,
              blur: 15, opacity: 0.6, period: 37),
        Cloud(color: Color(red: 1, green: 0.52, blue: 0.3), offset: 0.05, length: 0.5, thickness: 0.02,
              blur: 15, opacity: 0.5, period: 27),
    ]

    private func clouds(size: CGSize, line: CGFloat, time: Double) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.clouds.indices, id: \.self) { index in
                let cloud = Self.clouds[index]
                let sway = sin(time * 2 * .pi / cloud.period + Double(index)) * size.width * 0.06
                Capsule()
                    .fill(cloud.color)
                    .frame(width: size.width * cloud.length, height: max(4, size.height * cloud.thickness))
                    .blur(radius: cloud.blur)
                    .opacity(cloud.opacity * strength)
                    .position(x: size.width / 2 + sway, y: line + cloud.offset * size.height)
            }
        }
        .blendMode(.softLight)
    }

    /// The violet glow in the upper left, drifting a little.
    private func haze(size: CGSize, time: Double) -> some View {
        let drift = sin(time * 2 * .pi / 41)
        return Ellipse()
            .fill(Color(red: 0.56, green: 0.23, blue: 1))
            .frame(width: size.width * 0.5, height: size.height * 0.28)
            .blur(radius: 50)
            .opacity(0.45 * strength)
            .position(x: size.width * (0.18 + 0.04 * drift), y: size.height * (0.12 + 0.03 * drift))
    }

    // MARK: Sun and streaks

    /// One streak of light: its height around the horizon as a share of the scene, its
    /// thickness, and the seconds it takes to cross.
    private struct Streak {
        let color: Color
        let offset: CGFloat
        let thickness: CGFloat
        let period: Double
        let leftward: Bool
        let opacity: Double
    }

    private static let streaks = [
        Streak(color: Color(red: 0.44, green: 0.55, blue: 1), offset: -0.01, thickness: 14, period: 11,
               leftward: false, opacity: 1),
        Streak(color: Color(red: 1, green: 0.49, blue: 0.75), offset: -0.05, thickness: 9, period: 15,
               leftward: true, opacity: 1),
        Streak(color: Color(red: 0.75, green: 0.48, blue: 1), offset: 0.07, thickness: 18, period: 19,
               leftward: false, opacity: 0.75),
    ]

    /// Swells and fades once every 14 seconds.
    private func sun(width: CGFloat, time: Double) -> some View {
        let swell = (sin(time * 2 * .pi / 14) + 1) / 2
        let sunWidth = min(width * 0.62, 620)
        return Ellipse()
            .fill(EllipticalGradient(stops: [
                .init(color: Color(red: 1, green: 0.67, blue: 0.55).opacity(0.85), location: 0),
                .init(color: Color(red: 1, green: 0.37, blue: 0.59).opacity(0.3), location: 0.6),
                .init(color: .clear, location: 1),
            ]))
            .frame(width: sunWidth, height: sunWidth * 0.38)
            .blur(radius: 14)
            .scaleEffect(0.95 + 0.13 * swell)
            .opacity((0.75 + 0.25 * swell) * strength)
    }

    private func streak(_ streak: Streak, size: CGSize, line: CGFloat, time: Double) -> some View {
        let length = max(320, size.width * 0.6)
        let progress = time.truncatingRemainder(dividingBy: streak.period) / streak.period
        let travel = streak.leftward ? 1 - progress : progress
        return Ellipse()
            .fill(LinearGradient(colors: [.clear, streak.color, .clear], startPoint: .leading, endPoint: .trailing))
            .frame(width: length, height: streak.thickness)
            .blur(radius: 7)
            .opacity(streak.opacity * strength)
            .position(x: -length / 2 + travel * (size.width + length), y: line + streak.offset * size.height)
    }
}
