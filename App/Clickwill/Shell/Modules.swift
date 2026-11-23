import SwiftUI
import ClickwillModel
import ClickwillArtists
import ClickwillSongs
import ClickwillCD
import ClickwillDevice

/// The screen modules the window shows, and the only file in the app that names them.
///
/// A module is a library of its own (`Sources/<Module>`): it takes shared things from
/// `ClickwillShared` and the model, never from the app or another module. The window knows
/// a module only through `ModulePage`, so removing one means deleting its library and its
/// lines here.
enum ModulePage: Hashable {
    case artists(ArtistsPage)
    case songs(SongsPage)
    case cd(CDPage)
    case device(DevicePage)

    /// `--screen <name>`.
    init?(launchName: String) {
        if let page = ArtistsPage(launchName: launchName) { self = .artists(page); return }
        if let page = SongsPage(rawValue: launchName) { self = .songs(page); return }
        if let page = DevicePage(rawValue: launchName) { self = .device(page); return }
        return nil
    }

    /// The page shown under Diagnostics and Send Diagnostic Report opened from the command line.
    static let diagnosticsBackdrop: ModulePage? = .device(.overview)

    /// The page of a disc in a drive (`--audio-cd` in a launch for screenshots).
    static func disc(_ volume: URL) -> ModulePage? { .cd(.disc(volume)) }

    /// The page's name for the Back button.
    var title: String {
        switch self {
        case .artists(let page): page.title
        case .songs(let page): page.title
        case .cd: "Audio CD"
        case .device(let page): page.title
        }
    }

    @MainActor func windowTitle(in modules: ModuleStores) -> String {
        switch self {
        case .cd(let page): page.title(in: modules.cds)
        default: title
        }
    }

    @MainActor func subtitle(in model: LibraryModel, modules: ModuleStores) -> String {
        switch self {
        case .artists(let page): page.subtitle(in: model)
        case .songs(let page): page.subtitle(in: model)
        case .cd(let page): page.subtitle(in: modules.cds)
        case .device(let page): page.subtitle(in: model)
        }
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .artists(let page): ArtistsScreen(page: page)
        case .songs: SongsScreen()
        case .cd(let page): CDScreen(page: page)
        case .device(let page): DeviceScreen(page: page)
        }
    }

    /// Shown without a loaded library: a disc can be ripped with no iPod connected.
    var needsLibrary: Bool {
        switch self {
        case .cd: false
        case .artists, .songs, .device: true
        }
    }

    /// Where the window's Back button and Escape lead; nil hides the button.
    var parent: ModulePage? {
        switch self {
        case .artists(let page): page.parent.map(ModulePage.artists)
        case .songs, .cd, .device: nil
        }
    }

    /// The page whose sidebar row is selected while this one is shown.
    var root: ModulePage {
        var page = self
        while let parent = page.parent { page = parent }
        return page
    }

    /// Back from an album opened here returns here. Otherwise it returns to the first library screen.
    var keepsAlbumOrigin: Bool {
        switch self {
        case .artists: true
        case .songs, .cd, .device: false
        }
    }
}

/// The modules' rows in the sidebar's Library section, after the app's own.
struct ModuleLibraryItems: View {
    var body: some View {
        ArtistsSidebarItem { SidebarItem.module(.artists($0)) }
        SongsSidebarItem { SidebarItem.module(.songs($0)) }
    }
}

/// The modules' sections after the Library section.
struct ModuleSidebarSections: View {
    var body: some View {
        CDSidebarSection { SidebarItem.module(.cd($0)) }
        DeviceSidebarSection { SidebarItem.module(.device($0)) }
    }
}

/// The modules' items in the File menu.
struct ModuleFileMenuItems: View {
    var body: some View {
        AudioCDMenu()
    }
}

/// What one window keeps for its modules.
@MainActor
final class ModuleStores {
    let cds: AudioCDStore

    init(cdServices: CDServices) {
        cds = AudioCDStore(services: cdServices)
    }

    /// An inserted disc opens its page, as in Music, unless a sheet is open or another disc is
    /// being ripped. A removed disc takes its page down.
    func volumesChanged(inserted: Bool, removed: Bool, window: WindowState, sheetIsOpen: Bool) {
        let shownDisc: CDSession? = if case .module(.cd(let page)) = window.screen { cds.session(page.volume) } else { nil }
        if inserted, let disc = cds.refresh().first, !sheetIsOpen, shownDisc?.isRipping != true {
            window.show(.module(.cd(.disc(disc.volume))), animated: true)
        }
        if removed {
            cds.refresh()
            if case .module(.cd(let page)) = window.screen, cds.session(page.volume) == nil { window.showHome(animated: true) }
        }
    }
}

extension View {
    /// The modules' stores and what they ask the window to do, set once around the window's content.
    func modules(_ stores: ModuleStores, window: WindowState, playback: PlaybackController) -> some View {
        self
            .environment(stores.cds)
            .environment(\.cdActions, CDActions(importFiles: { window.showImport($0) }))
            .environment(\.artistsActions, ArtistsActions(
                show: { window.show(.module(.artists($0)), animated: true) },
                openAlbum: { window.open($0) }))
            .environment(\.songsActions, SongsActions(
                play: { playback.play($0, startingAt: $1, in: $2) },
                openAlbum: { window.open($0) }))
            .environment(\.deviceActions, DeviceActions(
                runDiagnostics: { window.showDiagnostics() },
                sendReport: { window.showSendReport(comment: $0) },
                sendFeedback: { window.showFeedback() },
                stopPlayback: { playback.stop() }))
    }
}
