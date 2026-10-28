import Foundation
import AppKit

/// Conditions for a write to the device to last.
///
/// Measured on an iPod Classic 7G: the database is rewritten by **Music on the Mac** when
/// the iPod is connected, if Music is running and finds a `Play Counts` file. It then merges
/// the statistics and regenerates the browse tables from its own index, erasing
/// everything we wrote into them. It leaves the track records alone. With Music
/// closed the database is untouchable. Hence the two conditions below.
public struct WritePreflight: Sendable {

    public enum Issue: Sendable, CustomStringConvertible, Equatable {
        /// The volume disappeared - this iPod's USB connection can be unstable.
        case volumeUnavailable
        /// Music is running. On the next play count merge it will regenerate the tables.
        case musicRunning
        /// The device holds unprocessed plays. They correspond to records
        /// by position, so any change to the track layout without merging them
        /// would assign them to the wrong songs.
        case pendingPlayCounts(tracks: Int)

        public var description: String {
            switch self {
            case .volumeUnavailable: "volume unavailable"
            case .musicRunning: "Music is running"
            case .pendingPlayCounts(let tracks): "Play Counts pending for \(tracks) tracks"
            }
        }

        /// Whether the problem blocks the write or only warns.
        public var isBlocking: Bool {
            switch self {
            case .volumeUnavailable: return true
            case .musicRunning: return true
            case .pendingPlayCounts: return false   // the writer merges them itself
            }
        }
    }

    public let issues: [Issue]
    public var blocking: [Issue] { issues.filter(\.isBlocking) }
    public var isClear: Bool { blocking.isEmpty }

    /// The block that stops the write. Permission to write with Music
    /// running (`ipodctl --allow-music`) lifts only this one - one rule for
    /// the database writer and the write transaction, which checks it before the first change.
    public func refusal(allowingMusic: Bool) -> Issue? {
        blocking.first { !(allowingMusic && $0 == .musicRunning) }
    }
}

/// How the write should behave given the preflight results.
public struct WriteOptions: Sendable {
    /// Allows writing with Music running. The write goes in, but changes to the browse
    /// tables will not survive the next play count merge.
    public var allowWhileMusicRunning = false
    /// Merges pending `Play Counts` into the database being written and deletes the file.
    /// Turning it off makes sense only in tests - without it Music has a reason to regenerate.
    public var mergePendingPlayCounts = true
    /// Digest of the database on which the caller started editing (`IPodDevice.digest(of:)`).
    /// When the database on the device has a different one, the write is rejected instead of overwriting someone else's changes.
    public var expectedSourceDigest: String? = nil
    /// Tracks removed when merging duplicates (`uniqueID` of the removed one ->
    /// the kept one). Their pending plays from `Play Counts` go to the copy
    /// that stays, instead of being lost with the record.
    public var playCountRedirects: [UInt32: UInt32] = [:]
    /// Whether Music is running. By default a real check; tests pass a constant,
    /// so the result does not depend on what is open on the Mac.
    public var isMusicRunning: @Sendable () -> Bool = IPodDevice.isMusicRunning

    public init() {}
}

extension IPodDevice {

    /// Checks the conditions before a write. Changes nothing.
    public func preflightForWriting(isMusicRunning: @Sendable () -> Bool = IPodDevice.isMusicRunning) -> WritePreflight {
        var issues: [WritePreflight.Issue] = []
        let manager = FileManager.default

        if !manager.fileExists(atPath: paths.iTunesDB.path) {
            issues.append(.volumeUnavailable)
        }
        if isMusicRunning() {
            issues.append(.musicRunning)
        }
        if manager.fileExists(atPath: paths.playCounts.path),
           let counts = try? readPlayCounts() {
            issues.append(.pendingPlayCounts(tracks: counts.pending.count))
        }
        return WritePreflight(issues: issues)
    }

    /// Whether the Music app is running.
    ///
    /// Through the `NSWorkspace` app list, not through `libproc`. In the Mac App Store
    /// sandbox `proc_listpids` returns zero processes (measured with a sandbox
    /// probe), so a check through `libproc` would say
    /// "Music closed" even with Music open - and the write would go through. `NSWorkspace` sees
    /// apps from the sandbox too. Recognition by bundle identifier,
    /// not by process name, which could belong to anything.
    public static func isMusicRunning() -> Bool {
        isApplicationRunning(bundleIdentifier: "com.apple.Music")
    }

    public static func isApplicationRunning(bundleIdentifier: String) -> Bool {
        return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}
