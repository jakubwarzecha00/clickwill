import SwiftUI
import ClickwillModel

/// A launch for screenshots and website recordings: what the window should do by itself before anyone
/// clicks anything. The window calls it at two moments - when it appears and when it
/// first loads the library - and does not know the launch flags itself.
///
/// A normal launch has no flags, and the script does nothing.
struct LaunchScript: Sendable {
    private let options: LaunchOptions

    init(options: LaunchOptions) {
        self.options = options
    }

    // MARK: - What the screens see

    /// A launch with nobody at the screen: no welcome.
    var isAutomated: Bool { options.isAutomated }

    /// `--demo`: a faked cursor hover in recordings (`DemoHover`).
    var listensForDemoHover: Bool { options.isDemo }

    /// `--editor`: the album edit panel open right away.
    var opensAlbumEditor: Bool { options.showsAlbumEditor }

    /// `--demo-cover <image>`: "Change Cover…" takes this file instead of the panel -
    /// a file choose panel in a demo recording would be unreadable.
    var coverFile: URL? { options.demoCover }

    /// `--demo --screen write-report`: a sample post-write report. Only
    /// when writing is blocked - a real report takes precedence.
    func sampleWriteReport(writesBlocked: Bool) -> WriteReport? {
        writesBlocked && options.screen == .writeReport ? .demo : nil
    }

    /// `--demo --screen diagnostics|rockbox`: a sample iPod Video, because a demo library is
    /// a backup on disk with nothing to measure.
    var sampleDiagnostics: SampleDiagnostics? {
        options.isDemo && ([.diagnostics, .rockbox, .sendReport].contains(options.screen)) ? .video : nil
    }

    /// The drive, the lookup and ripping a disc - in demo mode to a temporary
    /// folder and with a saved response instead of the network (`CDServices.app`).
    var cdServices: CDServices { .app(options) }

    // MARK: - Window

    /// `--audio-cd <folder with a .TOC.plist>`: the disc screen without a drive.
    /// `--cd-release` and `--cd-cover` (without `--demo`): the state after a lookup
    /// from a saved response, without the network.
    @MainActor func windowAppeared(window: WindowState, cds: AudioCDStore) {
        guard let fixture = options.audioCDFixture, let disc = cds.add(fixture: fixture) else { return }
        window.show(.audioCD(disc.volume))
        if !options.isDemo, let session = cds.session(disc.volume), let release = options.cdRelease,
           let data = try? Data(contentsOf: release),
           let releases = try? MusicBrainz.releases(fromJSON: data, discID: disc.discID, trackCount: disc.tracks.count),
           !releases.isEmpty {
            session.showFound(releases, cover: options.cdCover.flatMap { try? Data(contentsOf: $0) })
        }
    }

    /// After the first library load (the window makes sure it is once):
    /// `--centered N`, `--center <title or artist>`, `--loop-from`/`--loop-to`,
    /// `--screen …` and `--import <path>` (`--import-after <s>`: after this many
    /// seconds - a window with a sheet does not enter full screen, so full-screen
    /// screenshots turn it on first). It adds and writes nothing.
    @MainActor func libraryLoaded(window: WindowState, model: LibraryModel) {
        let albums = model.coverFlowDisplay
        if let index = options.centered, albums.indices.contains(index) { window.centered = index }
        if let index = options.center.flatMap({ Self.albumIndex($0, in: albums) }) { window.centered = index }
        if let loop = options.coverFlowLoop, let from = Self.albumIndex(loop.from, in: albums),
           let to = Self.albumIndex(loop.to, in: albums), from != to {
            window.centered = from
            Task { await Self.runCoverFlowLoop(window: window, from: from, to: to) }
        }
        switch options.screen {
        case .album: if albums.indices.contains(window.centered) { window.show(.album(albums[window.centered])) }
        case .albums:
            // `--centered N` then concerns the wheel: the N-th album of the Albums menu.
            if let index = options.centered, model.albumsDisplay.indices.contains(index) { window.albumsCentered = index }
            window.show(.albums)
        case .reorder: window.show(.reorder)
        case .songs: window.show(.songs)
        case .overview: window.show(.overview)
        case .backups: window.show(.backups)
        case .pending, .writeReport: window.showPending()
        case .diagnostics: window.show(.overview); window.showDiagnostics()
        case .rockbox: window.show(.overview); window.showRockboxReport()
        case .sendReport: window.show(.overview); window.showSendReport()
        case .coverflow, nil: break
        }
        if let url = options.importURL {
            let delay = options.importDelay
            Task {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                window.showImport([url])
            }
        }
    }

    /// An album by title, then by artist, and finally a title containing the name.
    private static func albumIndex(_ name: String, in albums: [AlbumCard]) -> Int? {
        albums.firstIndex { $0.displayTitle.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? albums.firstIndex { $0.displayArtist.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? albums.firstIndex { $0.displayTitle.localizedCaseInsensitiveContains(name) }
    }

    /// Cover Flow moves album by album from `from` to `to` and back, one
    /// step per beat. At the ends it stands for two beats. The steps follow the clock from the start,
    /// not from the previous step, so the motion is strictly periodic: any cut
    /// segment one period long loops in a video without a seam.
    @MainActor private static func runCoverFlowLoop(window: WindowState, from: Int, to: Int) async {
        let beat = Duration.milliseconds(1200)
        let direction = to > from ? 1 : -1
        let forward = Array(stride(from: from + direction, through: to, by: direction))
        let backward = Array(stride(from: to - direction, through: from, by: -direction))
        let slots = [from] + forward + [to] + backward
        FileHandle.standardError.write(Data("coverflow-loop \(slots.count) beats of 1.2 s\n".utf8))
        let clock = ContinuousClock()
        let start = clock.now
        for tick in 0... {
            try? await clock.sleep(until: start + beat * tick)
            let target = slots[tick % slots.count]
            if target != window.centered {
                withAnimation(.spring(duration: 0.8, bounce: 0.08)) { window.centered = target }
            }
        }
    }
}
