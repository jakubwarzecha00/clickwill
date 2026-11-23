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
        guard let fixture = options.audioCDFixture, let disc = cds.add(fixture: fixture),
              let page = ModulePage.disc(disc.volume) else { return }
        window.show(.module(page))
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
    @MainActor func libraryLoaded(window: WindowState, model: LibraryModel, modules: ModuleStores) {
        let albums = model.coverFlowDisplay
        if let index = options.centered, albums.indices.contains(index) { modules.centerCoverFlow(at: index) }
        if let index = options.center.flatMap({ Self.albumIndex($0, in: albums) }) { modules.centerCoverFlow(at: index) }
        if let loop = options.coverFlowLoop, let from = Self.albumIndex(loop.from, in: albums),
           let to = Self.albumIndex(loop.to, in: albums), from != to {
            modules.loopCoverFlow(from: from, to: to)
        }
        switch options.screen {
        case .album:
            if let album = modules.coverFlowAlbum(in: model), let page = ModulePage.album(album) { window.show(.module(page)) }
        case .pending, .writeReport: window.showPending()
        case .diagnostics: showDiagnosticsBackdrop(window); window.showDiagnostics()
        case .rockbox: showDiagnosticsBackdrop(window); window.showRockboxReport()
        case .sendReport: showDiagnosticsBackdrop(window); window.showSendReport()
        case .developerMode: _ = ExperimentalConsent.askDeveloperMode()
        case nil: break
        }
        if let page = options.modulePage {
            if let index = options.centered { modules.center(at: index, on: page, in: model) }
            window.show(.module(page))
        }
        if let url = options.importURL {
            let delay = options.importDelay
            Task {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                window.showImport([url])
            }
        }
    }

    /// The page under Diagnostics opened from the command line, as when opened from it by hand.
    @MainActor private func showDiagnosticsBackdrop(_ window: WindowState) {
        if let page = ModulePage.diagnosticsBackdrop { window.show(.module(page)) }
    }

    /// An album by title, then by artist, and finally a title containing the name.
    private static func albumIndex(_ name: String, in albums: [AlbumCard]) -> Int? {
        albums.firstIndex { $0.displayTitle.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? albums.firstIndex { $0.displayArtist.localizedCaseInsensitiveCompare(name) == .orderedSame }
            ?? albums.firstIndex { $0.displayTitle.localizedCaseInsensitiveContains(name) }
    }
}
