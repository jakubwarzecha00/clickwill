import Foundation
import Observation

/// Discs in the drive and what the user is doing with each of them. Kept outside
/// the screen, because ripping must go on when the user moves to the albums.
@MainActor @Observable
public final class AudioCDStore {
    public private(set) var discs: [AudioCD] = []
    private var sessions: [URL: CDSession] = [:]
    @ObservationIgnored private let services: CDServices

    public init(services: CDServices) {
        self.services = services
    }

    /// Refreshes the list of discs. Returns the discs that just appeared.
    @discardableResult
    public func refresh() -> [AudioCD] {
        let now = services.drive.mounted()
        let added = now.filter { disc in !discs.contains { $0.volume == disc.volume } }
        discs = now
        for disc in added where sessions[disc.volume] == nil { sessions[disc.volume] = CDSession(disc: disc, services: services) }
        for url in sessions.keys where !now.contains(where: { $0.volume == url }) {
            sessions[url]?.cancelRip()
            sessions[url] = nil
        }
        return added
    }

    public func session(_ volume: URL) -> CDSession? { sessions[volume] }

    /// A folder with a `.TOC.plist` that pretends to be a disc (`--audio-cd`). It disappears
    /// on the first refresh after anything is mounted - enough for a screenshot.
    public func add(fixture folder: URL) -> AudioCD? {
        guard let disc = try? AudioCD(volume: folder) else { return nil }
        // The fake replaces the discs from the drive - there is one drive, and two discs in
        // a screenshot would look fake.
        discs = [disc]
        sessions[disc.volume] = CDSession(disc: disc, services: services)
        return disc
    }
}
