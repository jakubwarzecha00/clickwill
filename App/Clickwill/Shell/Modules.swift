import SwiftUI
import ClickwillModel
import ClickwillCoverFlow
import ClickwillArtists
import ClickwillSongs
import ClickwillCD
import ClickwillAlbum
import ClickwillDevice

/// The screen modules the window shows, and the only file in the app that names them.
///
/// A module is a library of its own (`Sources/<Module>`): it takes shared things from
/// `ClickwillShared` and the model, never from the app or another module. The window knows
/// a module only through `ModulePage`, so removing one means deleting its library and its
/// lines here.
enum ModulePage: Hashable {
    case coverFlow(CoverFlowPage)
    case artists(ArtistsPage)
    case songs(SongsPage)
    case cd(CDPage)
    case album(AlbumPage)
    case device(DevicePage)

    /// `--screen <name>`.
    init?(launchName: String) {
        if let page = CoverFlowPage(rawValue: launchName) { self = .coverFlow(page); return }
        if let page = ArtistsPage(launchName: launchName) { self = .artists(page); return }
        if let page = SongsPage(rawValue: launchName) { self = .songs(page); return }
        if let page = DevicePage(rawValue: launchName) { self = .device(page); return }
        return nil
    }

    /// The screen a new window starts on, before the library says what the iPod has (`isAvailable`).
    static let start: ModulePage? = .coverFlow(.coverFlow)

    /// The first library screen, or nil to let the app fall back to Albums.
    @MainActor static func home(in model: LibraryModel) -> ModulePage? {
        CoverFlowPage.coverFlow.isAvailable(in: model) ? .coverFlow(.coverFlow) : nil
    }

    /// The page shown under Diagnostics and Send Diagnostic Report opened from the command line.
    static let diagnosticsBackdrop: ModulePage? = .device(.overview)

    /// The page of a disc in a drive (`--audio-cd` in a launch for screenshots).
    static func disc(_ volume: URL) -> ModulePage? { .cd(.disc(volume)) }

    /// The page an album opens on, from Cover Flow, the Albums wheel or a module.
    static func album(_ card: AlbumCard) -> ModulePage? { .album(.album(card)) }

    /// The album this page shows; Back centers it on the screen it returns to.
    var shownAlbum: AlbumCard? {
        if case .album(let page) = self { page.album } else { nil }
    }

    /// The page's name for the Back button.
    var title: String {
        switch self {
        case .coverFlow(let page): page.title
        case .artists(let page): page.title
        case .songs(let page): page.title
        case .cd: "Audio CD"
        case .album(let page): page.album.displayTitle
        case .device(let page): page.title
        }
    }

    @MainActor func windowTitle(in model: LibraryModel, modules: ModuleStores) -> String {
        switch self {
        case .cd(let page): page.title(in: modules.cds)
        case .album(let page): page.title(in: model)
        default: title
        }
    }

    @MainActor func subtitle(in model: LibraryModel, modules: ModuleStores) -> String {
        switch self {
        case .coverFlow(let page): page.subtitle(in: model)
        case .artists(let page): page.subtitle(in: model)
        case .songs(let page): page.subtitle(in: model)
        case .cd(let page): page.subtitle(in: modules.cds)
        case .album(let page): page.subtitle(in: model)
        case .device(let page): page.subtitle(in: model)
        }
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .coverFlow(let page): CoverFlowModuleScreen(page: page)
        case .artists(let page): ArtistsScreen(page: page)
        case .songs: SongsScreen()
        case .cd(let page): CDScreen(page: page)
        case .album(let page): AlbumModuleScreen(page: page)
        case .device(let page): DeviceScreen(page: page)
        }
    }

    /// Shown without a loaded library: a disc can be ripped with no iPod connected.
    var needsLibrary: Bool {
        switch self {
        case .cd: false
        case .coverFlow, .artists, .songs, .album, .device: true
        }
    }

    /// False takes the window back home, e.g. Cover Flow once an iPod without it loads.
    @MainActor func isAvailable(in model: LibraryModel) -> Bool {
        switch self {
        case .coverFlow(let page): page.isAvailable(in: model)
        case .artists, .songs, .cd, .album, .device: true
        }
    }

    /// A key the window passes on while this page is shown; the scene holds the focus, not the page.
    @MainActor func handle(_ key: KeyEquivalent, model: LibraryModel, modules: ModuleStores, window: WindowState) -> KeyPress.Result {
        switch self {
        case .coverFlow: modules.coverFlow.handle(key, albums: model.coverFlowDisplay, open: window.open)
        case .artists, .songs, .cd, .album, .device: .ignored
        }
    }

    /// Where the window's Back button and Escape lead; nil hides the button.
    var parent: ModulePage? {
        switch self {
        case .artists(let page): page.parent.map(ModulePage.artists)
        case .coverFlow, .songs, .cd, .album, .device: nil
        }
    }

    /// The page whose sidebar row is selected while this one is shown.
    var root: ModulePage {
        var page = self
        while let parent = page.parent { page = parent }
        return page
    }

    /// Shown over the screen it was opened from, which keeps its sidebar row; Back returns there.
    var opensOver: Bool {
        switch self {
        case .album: true
        case .coverFlow, .artists, .songs, .cd, .device: false
        }
    }

    /// Back from a page opened over this one returns here. Otherwise it returns to the first library screen.
    var staysAsOrigin: Bool {
        switch self {
        case .coverFlow, .artists: true
        case .songs, .cd, .album, .device: false
        }
    }
}

/// The modules' rows in the sidebar's Library section. Albums is still the app's own row,
/// so each row says on which side of it it goes.
struct ModuleLibraryItems: View {
    enum Placement { case beforeAlbums, afterAlbums }
    let placement: Placement

    var body: some View {
        switch placement {
        case .beforeAlbums:
            CoverFlowSidebarItem { SidebarItem.module(.coverFlow($0)) }
        case .afterAlbums:
            ArtistsSidebarItem { SidebarItem.module(.artists($0)) }
            SongsSidebarItem { SidebarItem.module(.songs($0)) }
        }
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
    let albumOptions: AlbumOptions
    let coverFlow = CoverFlowState()

    init(launch: LaunchScript) {
        cds = AudioCDStore(services: launch.cdServices)
        albumOptions = AlbumOptions(editorShown: launch.opensAlbumEditor, coverFile: launch.coverFile)
    }

    /// An album that was open stays in the middle of Cover Flow once the window goes back.
    func center(_ album: AlbumCard, in model: LibraryModel) {
        coverFlow.center(album, in: model.coverFlowDisplay)
    }

    /// `--centered`, `--center` and `--screen album` in a launch for screenshots.
    func centerCoverFlow(at index: Int) { coverFlow.centered = index }

    func coverFlowAlbum(in model: LibraryModel) -> AlbumCard? {
        let albums = model.coverFlowDisplay
        return albums.indices.contains(coverFlow.centered) ? albums[coverFlow.centered] : nil
    }

    /// `--loop-from`/`--loop-to` for looping website videos.
    func loopCoverFlow(from: Int, to: Int) {
        coverFlow.centered = from
        Task { await coverFlow.runLoop(from: from, to: to) }
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
        var reorder: (@MainActor @Sendable () -> Void)?
        if AppFeatures.reorderAlbums { reorder = { window.showReorder() } }
        return self
            .environment(stores.cds)
            .environment(stores.coverFlow)
            .environment(\.coverFlowActions, CoverFlowActions(openAlbum: { window.open($0) }, reorder: reorder))
            .environment(\.cdActions, CDActions(importFiles: { window.showImport($0) }))
            .environment(\.artistsActions, ArtistsActions(
                show: { window.show(.module(.artists($0)), animated: true) },
                openAlbum: { window.open($0) }))
            .environment(\.songsActions, SongsActions(
                play: { playback.play($0, startingAt: $1, in: $2) },
                openAlbum: { window.open($0) }))
            .environment(\.albumOptions, stores.albumOptions)
            .environment(\.albumActions, AlbumActions(
                play: { playback.play($0, startingAt: $1, in: $2) },
                playingTrackID: { playback.currentTrack?.id },
                close: { window.closeOver(animated: $0) }))
            .environment(\.deviceActions, DeviceActions(
                runDiagnostics: { window.showDiagnostics() },
                sendReport: { window.showSendReport(comment: $0) },
                sendFeedback: { window.showFeedback() },
                stopPlayback: { playback.stop() }))
    }
}
