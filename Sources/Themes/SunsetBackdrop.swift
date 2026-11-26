import SwiftUI

/// The Vice scene, from the bottom up: the sky (`SunsetSky`), drifting clouds and the
/// moving light of the low sun (`SunsetLight`), and palms in front of it all (`PalmGrove`).
///
/// It covers the palette's own scene colors. It moves only for a moment when the scene
/// appears or another album is chosen (`SunsetMotion`), at most 30 times a second, and
/// otherwise stands still at rest. Reduce Motion keeps it at rest.
struct SunsetBackdrop: View {
    /// Where the floor begins, as a share of the height; 1 puts the horizon on the bottom edge.
    let horizon: CGFloat
    /// 0 to 1: below 1, night is laid over the picture and the light is fainter, so titles
    /// anywhere on the scene stay readable.
    let strength: Double
    /// The album being looked at; a change sets the scene moving.
    let moment: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var motion = SunsetMotion()
    /// Set while `motion` runs, cleared when it ends, so the timeline stops.
    @State private var moving = false

    var body: some View {
        let paused = !moving || reduceMotion || activeState == .inactive
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            // Once the motion has ended, the timeline's date may still be a moment from the
            // middle of it (the window was in the background), so rest is set explicitly.
            let amplitude = moving && !reduceMotion ? motion.amplitude(at: timeline.date) : 0
            GeometryReader { geometry in
                let size = geometry.size
                let line = horizon * size.height
                ZStack(alignment: .topLeading) {
                    LinearGradient(stops: SunsetSky.stops(horizon: horizon), startPoint: .top, endPoint: .bottom)
                    SunsetClouds(size: size, line: line, time: time, motion: amplitude, strength: strength)
                    SunsetLight(size: size, line: line, time: time, motion: amplitude, strength: strength)
                    PalmGrove(size: size, time: time, motion: amplitude)
                    ViceColors.night.opacity((1 - strength) * 0.8)
                }
                .compositingGroup()
            }
        }
        .clipped()
        .onAppear(perform: startMoving)
        .onChange(of: moment) { startMoving() }
        .task(id: motion.end) {
            try? await Task.sleep(for: .seconds(max(0, motion.end.timeIntervalSinceNow)))
            // A newer trigger cancels this wait; its own wait ends the motion later.
            guard !Task.isCancelled else { return }
            moving = false
        }
    }

    private func startMoving() {
        motion.trigger(at: .now)
        moving = true
    }
}
