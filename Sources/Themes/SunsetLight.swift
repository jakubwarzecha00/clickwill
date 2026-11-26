import SwiftUI

/// Soft red and orange clouds drifting across the sky. Laid on with soft light, so they
/// tint the sky rather than cover it.
struct SunsetClouds: View {
    let size: CGSize
    /// The horizon's distance from the top, in points.
    let line: CGFloat
    let time: Double
    let strength: Double

    /// A blurred brush stroke of color: its height around the horizon, its length and
    /// thickness as shares of the scene, and how slowly it sways.
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
        Cloud(color: Color(red: 1, green: 0.42, blue: 0.45), offset: -0.12, length: 0.95, thickness: 0.05,
              blur: 25, opacity: 0.5, period: 31),
        Cloud(color: Color(red: 1, green: 0.66, blue: 0.4), offset: -0.22, length: 0.6, thickness: 0.025,
              blur: 15, opacity: 0.55, period: 23),
        Cloud(color: Color(red: 1, green: 0.66, blue: 0.4), offset: -0.06, length: 0.7, thickness: 0.03,
              blur: 15, opacity: 0.55, period: 37),
        Cloud(color: Color(red: 1, green: 0.6, blue: 0.45), offset: 0.05, length: 0.5, thickness: 0.02,
              blur: 15, opacity: 0.45, period: 27),
    ]

    var body: some View {
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
}

/// A low sun that slowly swells and fades on the horizon, and streaks of blue, pink and
/// violet light crossing it. Laid on with screen, so it only ever adds light.
struct SunsetLight: View {
    let size: CGSize
    /// The horizon's distance from the top, in points.
    let line: CGFloat
    let time: Double
    let strength: Double

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            sun.position(x: size.width / 2, y: line)
            ForEach(Self.streaks.indices, id: \.self) { index in
                streak(Self.streaks[index])
            }
        }
        .blendMode(.screen)
    }

    /// A wide peach glow that swells and fades once every 14 seconds.
    private var sun: some View {
        let swell = (sin(time * 2 * .pi / 14) + 1) / 2
        let width = min(size.width * 0.9, 900)
        return Ellipse()
            .fill(EllipticalGradient(stops: [
                .init(color: Color(red: 1, green: 0.77, blue: 0.6).opacity(0.85), location: 0),
                .init(color: Color(red: 1, green: 0.6, blue: 0.54).opacity(0.35), location: 0.6),
                .init(color: .clear, location: 1),
            ]))
            .frame(width: width, height: width * 0.4)
            .blur(radius: 18)
            .scaleEffect(0.95 + 0.13 * swell)
            .opacity((0.75 + 0.25 * swell) * strength)
    }

    private func streak(_ streak: Streak) -> some View {
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
