import Testing
@testable import ClickwillModel

@Suite("Preview queue")
struct PlaybackQueueTests {
    private func track(_ id: UInt32, missing: Bool = false) -> TrackRow {
        TrackRow(id: id, persistentID: UInt64(id), title: "Track \(id)", artist: "Artist",
                 number: id, duration: 60, playCount: 0, fileMissing: missing)
    }

    @Test("an empty queue and only missing files")
    func unavailable() {
        for tracks in [[], [track(1, missing: true), track(2, missing: true)]] {
            var queue = PlaybackQueue(tracks)
            #expect(queue.currentIndex == nil)
            #expect(queue.currentTrack == nil)
            #expect(queue.next() == nil)
            #expect(queue.previous() == nil)
            #expect(queue.jump(to: 1) == nil)
        }
    }

    @Test("skipping missing files at the start, in the middle and at the end in both directions")
    func skipsMissing() {
        let tracks = [track(1, missing: true), track(2), track(3, missing: true),
                      track(4, missing: true), track(5), track(6, missing: true)]
        var queue = PlaybackQueue(tracks)
        #expect(queue.tracks == tracks)
        #expect(queue.currentIndex == 1)
        #expect(queue.previous() == nil)
        #expect(queue.next()?.id == 5)
        #expect(queue.next() == nil)
        #expect(queue.currentIndex == 4)
        #expect(queue.previous()?.id == 2)
        #expect(queue.previous() == nil)
        #expect(queue.currentIndex == 1)
    }

    @Test("one track does not loop the queue")
    func singleTrack() {
        var queue = PlaybackQueue([track(1)])
        #expect(queue.next() == nil)
        #expect(queue.previous() == nil)
        #expect(queue.currentTrack?.id == 1)
    }

    @Test("start from the chosen track or the next available one")
    func startingTrack() {
        let tracks = [track(1), track(2, missing: true), track(3), track(4, missing: true)]
        #expect(PlaybackQueue(tracks, startingAt: tracks[2]).currentIndex == 2)
        #expect(PlaybackQueue(tracks, startingAt: tracks[1]).currentIndex == 2)
        #expect(PlaybackQueue(tracks, startingAt: tracks[3]).currentIndex == nil)
        #expect(PlaybackQueue(tracks, startingAt: track(99)).currentIndex == 0)
    }

    @Test("a jump by identifier, and rejecting a missing and an unknown track")
    func jump() {
        var queue = PlaybackQueue([track(10), track(20, missing: true), track(30)])
        #expect(queue.jump(to: 30)?.id == 30)
        #expect(queue.currentIndex == 2)
        #expect(queue.jump(to: 20) == nil)
        #expect(queue.jump(to: 99) == nil)
        #expect(queue.currentIndex == 2)
        #expect(queue.jump(to: 10)?.id == 10)
        #expect(queue.next()?.id == 30)
    }
}
