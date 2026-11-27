import Foundation
import Testing
@testable import ClickwillThemes

struct SunsetMotionTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func standsStillUntilSomethingSetsItMoving() {
        let motion = SunsetMotion()
        #expect(motion.amplitude(at: start) == 0)
        #expect(!motion.isMoving(at: start))
    }

    @Test func risesMovesFullyAndComesBackToRest() {
        var motion = SunsetMotion()
        motion.trigger(at: start)
        #expect(motion.amplitude(at: start) == 0)
        #expect(motion.amplitude(at: at(0.5)) > 0 && motion.amplitude(at: at(0.5)) < 1)
        #expect(motion.amplitude(at: at(3)) == 1)
        #expect(motion.isMoving(at: at(5.9)))
        #expect(motion.amplitude(at: at(SunsetMotion.duration)) == 0)
        #expect(!motion.isMoving(at: at(SunsetMotion.duration)))
    }

    @Test func anotherAlbumWhileMovingOnlyPushesTheEnd() {
        var motion = SunsetMotion()
        motion.trigger(at: start)
        let before = motion.amplitude(at: at(0.5))
        motion.trigger(at: at(0.5))
        #expect(motion.amplitude(at: at(0.5)) == before)
        #expect(motion.isMoving(at: at(6.4)))
        #expect(!motion.isMoving(at: at(6.5)))
    }

    /// Choosing an album while the motion fades picks it up from where it is, without a jump.
    @Test func anotherAlbumWhileFadingRisesWithoutAJump() {
        var motion = SunsetMotion()
        motion.trigger(at: start)
        let moment = at(5.5)
        let before = motion.amplitude(at: moment)
        #expect(before > 0 && before < 1)
        motion.trigger(at: moment)
        #expect(abs(motion.amplitude(at: moment) - before) <= 0.01)
        #expect(motion.amplitude(at: moment.addingTimeInterval(0.1)) > before)
        #expect(motion.amplitude(at: moment.addingTimeInterval(3)) == 1)
    }

    @Test func aTriggerAtRestStartsFromStill() {
        var motion = SunsetMotion()
        motion.trigger(at: start)
        motion.trigger(at: at(20))
        #expect(motion.amplitude(at: at(20)) == 0)
        #expect(motion.isMoving(at: at(20)))
    }
}
