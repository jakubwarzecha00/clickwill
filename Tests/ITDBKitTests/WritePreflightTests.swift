import AppKit
import Foundation
import Testing
@testable import ITDBKit

@Suite("Write preflight")
struct WritePreflightTests {

    @Test("a missing volume and Music block, pending plays only warn")
    func blockingClassification() {
        #expect(WritePreflight.Issue.volumeUnavailable.isBlocking)
        #expect(WritePreflight.Issue.musicRunning.isBlocking)
        #expect(!WritePreflight.Issue.pendingPlayCounts(tracks: 3).isBlocking)

        let mixed = WritePreflight(issues: [.pendingPlayCounts(tracks: 3)])
        #expect(mixed.isClear)
        let blocked = WritePreflight(issues: [.pendingPlayCounts(tracks: 3), .musicRunning])
        #expect(!blocked.isClear)
        #expect(blocked.blocking == [.musicRunning])
    }

    /// A source of truth independent of the tested code: AppKit knows apps by bundle id.
    static var realMusicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    @Test("a process named Music from outside Music.app is not taken for Music",
          .enabled(if: !realMusicIsRunning, "the real Music is running - the test cannot tell them apart"))
    func musicDetectionIsPathBased() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-preflight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appendingPathComponent("Music")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: fake.path)

        let process = Process()
        process.executableURL = fake
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        #expect(!IPodDevice.isMusicRunning())
    }

    @Test("the real Music is detected when it runs",
          .enabled(if: realMusicIsRunning, "Music is not running - there is nothing to detect"))
    func detectsRealMusic() {
        #expect(IPodDevice.isMusicRunning())
    }

    @Test("permission to write with Music running lifts only that block")
    func refusalAllowingMusic() {
        let both = WritePreflight(issues: [.musicRunning, .volumeUnavailable, .pendingPlayCounts(tracks: 3)])
        #expect(both.refusal(allowingMusic: false) == .musicRunning)
        #expect(both.refusal(allowingMusic: true) == .volumeUnavailable)
        let music = WritePreflight(issues: [.musicRunning, .pendingPlayCounts(tracks: 3)])
        #expect(music.refusal(allowingMusic: true) == nil, "plays do not block - the writer merges them")
    }
}
