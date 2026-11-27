import Foundation

/// How strongly the Vice scene moves: 0 at rest, 1 in full motion.
///
/// Each trigger (the scene appears, another album is chosen) keeps the scene moving for
/// `duration` seconds: the motion rises over `rampUp`, then fades over `rampDown` back to
/// rest, where the scene stands still and costs nothing to draw. A trigger while it is still
/// moving pushes the end further; while it fades, it also rises again from the strength it
/// has, so there is never a jump.
struct SunsetMotion: Equatable {
    static let duration: TimeInterval = 6
    static let rampUp: TimeInterval = 1
    static let rampDown: TimeInterval = 1.5

    private(set) var start = Date.distantPast
    private(set) var end = Date.distantPast

    func isMoving(at now: Date) -> Bool {
        start <= now && now < end
    }

    /// Eased, so the motion starts and stops softly.
    func amplitude(at now: Date) -> Double {
        let share = progress(at: now)
        return share * share * (3 - 2 * share)
    }

    mutating func trigger(at now: Date) {
        if !isMoving(at: now) {
            start = now
        } else if now.timeIntervalSince(start) / Self.rampUp > end.timeIntervalSince(now) / Self.rampDown {
            // Fading out: rise again from the strength it has now.
            start = now.addingTimeInterval(-progress(at: now) * Self.rampUp)
        }
        end = now.addingTimeInterval(Self.duration)
    }

    /// The linear strength, before easing: the lower of the rise and the fade.
    private func progress(at now: Date) -> Double {
        guard isMoving(at: now) else { return 0 }
        let rising = now.timeIntervalSince(start) / Self.rampUp
        let fading = end.timeIntervalSince(now) / Self.rampDown
        return min(1, rising, fading)
    }
}
