import SwiftUI
import ClickwillShared

/// The Vice scene, from the bottom up: the sky (`SunsetSky`), drifting clouds and the
/// moving light of the low sun (`SunsetLight`), and palms in front of it all (`PalmGrove`).
///
/// It covers the palette's own scene colors. It holds still while Reduce Motion is on or the
/// window is not in front, and redraws at most 30 times a second.
struct SunsetBackdrop: View {
    /// Where the floor begins, as a share of the height; 1 puts the horizon on the bottom edge.
    let horizon: CGFloat
    /// 0 to 1: below 1, night is laid over the picture and the light is fainter, so titles
    /// anywhere on the scene stay readable.
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
                    LinearGradient(stops: SunsetSky.stops(horizon: horizon), startPoint: .top, endPoint: .bottom)
                    SunsetClouds(size: size, line: line, time: time, strength: strength)
                    SunsetLight(size: size, line: line, time: time, strength: strength)
                    PalmGrove(size: size, time: time)
                    ViceColors.night.opacity((1 - strength) * 0.8)
                }
                .compositingGroup()
            }
        }
        .clipped()
    }
}
