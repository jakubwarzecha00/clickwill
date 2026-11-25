import SwiftUI
import ClickwillModel
import ClickwillShared
import ClickwillCoverFlow
import ClickwillAlbums
import ClickwillArtists
import ClickwillSongs
import ClickwillCD
import ClickwillAlbum
import ClickwillDevice
import ClickwillImport
import ClickwillChanges
import ClickwillThemes
import ITDBKit

/// The screen modules the window shows, and the only file in the app that names them.
///
/// A module is a library of its own (`Sources/<Module>`): it takes shared things from
/// `ClickwillShared` and the model, never from the app or another module. The window knows
/// a module only through `ModulePage`, so removing one means deleting its library and its
/// lines here.
enum ModulePage: Hashable {
    case coverFlow(CoverFlowPage)
    case albums(AlbumsPage)
    case artists(ArtistsPage)
    case songs(SongsPage)
    case cd(CDPage)
    case album(AlbumPage)
    case device(DevicePage)
    /// The app's settings (`SettingsView`): not a module, but a page of the window like them.
    case settings

    /// `--screen <name>`.
    init?(launchName: String) {
        if launchName == "settings" { self = .settings; return }
        if let page = CoverFlowPage(rawValue: launchName) { self = .coverFlow(page); return }
        if let page = AlbumsPage(rawValue: launchName) { self = .albums(page); return }
        if let page = ArtistsPage(launchName: launchName) { self = .artists(page); return }
        if let page = SongsPage(rawValue: launchName) { self = .songs(page); return }
        if let page = DevicePage(rawValue: launchName) { self = .device(page); return }
        return nil
    }

    /// The screen a new window starts on, before the library says what the iPod has (`isAvailable`).
    static let start: ModulePage = .coverFlow(.coverFlow)

    /// The first library screen: Cover Flow, and on an iPod without it, Albums.
    @MainActor static func home(in model: LibraryModel) -> ModulePage {
        CoverFlowPage.coverFlow.isAvailable(in: model) ? .coverFlow(.coverFlow) : .albums(.albums)
    }

    /// Reorder Albums, from Cover Flow's toolbar and the View menu.
    static let reorder: ModulePage = .albums(.reorder)

    /// The page shown under Diagnostics and Send Diagnostic Report opened from the command line.
    static let diagnosticsBackdrop: ModulePage = .device(.overview)

    /// The page of a disc in a drive (`--audio-cd` in a launch for screenshots).
    static func disc(_ volume: URL) -> ModulePage { .cd(.disc(volume)) }

    /// The page an album opens on, from Cover Flow, the Albums wheel or a module.
    static func album(_ card: AlbumCard) -> ModulePage { .album(.album(card)) }

    /// The album this page shows; Back centers it on the screen it returns to.
    var shownAlbum: AlbumCard? {
        if case .album(let page) = self { page.album } else { nil }
    }

    /// The page's name for the Back button.
    var title: String {
        switch self {
        case .coverFlow(let page): page.title
        case .albums(let page): page.title
        case .artists(let page): page.title
        case .songs(let page): page.title
        case .cd: "Audio CD"
        case .album(let page): page.album.displayTitle
        case .device(let page): page.title
        case .settings: "Settings"
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
        case .albums(let page): page.subtitle(in: model)
        case .artists(let page): page.subtitle(in: model)
        case .songs(let page): page.subtitle(in: model)
        case .cd(let page): page.subtitle(in: modules.cds)
        case .album(let page): page.subtitle(in: model)
        case .device(let page): page.subtitle(in: model)
        case .settings: ""
        }
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .coverFlow(let page): CoverFlowModuleScreen(page: page)
        case .albums(let page): AlbumsScreen(page: page)
        case .artists(let page): ArtistsScreen(page: page)
        case .songs: SongsScreen()
        case .cd(let page): CDScreen(page: page)
        case .album(let page): AlbumModuleScreen(page: page)
        case .device(let page): DeviceScreen(page: page)
        case .settings: SettingsView()
        }
    }

    /// Shown without a loaded library: a disc can be ripped with no iPod connected, and
    /// settings are there before any iPod.
    var needsLibrary: Bool {
        switch self {
        case .cd, .settings: false
        case .coverFlow, .albums, .artists, .songs, .album, .device: true
        }
    }

    /// False takes the window back home, e.g. Cover Flow once an iPod without it loads.
    @MainActor func isAvailable(in model: LibraryModel) -> Bool {
        switch self {
        case .coverFlow(let page): page.isAvailable(in: model)
        case .albums, .artists, .songs, .cd, .album, .device, .settings: true
        }
    }

    /// Stays on screen when the iPod is unplugged; every other page goes back home.
    var staysWhenIPodLeaves: Bool {
        self == .settings
    }

    /// A key the window passes on while this page is shown; the scene holds the focus, not the page.
    @MainActor func handle(_ press: KeyPress, model: LibraryModel, modules: ModuleStores, window: WindowState) -> KeyPress.Result {
        switch self {
        case .coverFlow:
            modules.coverFlow.handle(press.key, albums: model.coverFlowDisplay, open: window.open)
        case .albums(.albums):
            modules.albums.handle(press.key, characters: press.characters, albums: modules.albums.shown(from: model.albumsDisplay),
                                  letter: model.menuLetter(of:), open: window.open)
        case .albums(.reorder), .artists, .songs, .cd, .album, .device, .settings:
            .ignored
        }
    }

    /// Where the window's Back button and Escape lead; nil hides the button.
    var parent: ModulePage? {
        switch self {
        case .artists(let page): page.parent.map(ModulePage.artists)
        case .coverFlow, .albums, .songs, .cd, .album, .device, .settings: nil
        }
    }

    /// The page whose sidebar row is selected while this one is shown.
    var root: ModulePage {
        if case .albums(let page) = self { return .albums(page.sidebarPage) }
        var page = self
        while let parent = page.parent { page = parent }
        return page
    }

    /// Shown over the screen it was opened from, which keeps its sidebar row; Back returns there.
    var opensOver: Bool {
        switch self {
        case .album: true
        case .coverFlow, .albums, .artists, .songs, .cd, .device, .settings: false
        }
    }

    /// Back from a page opened over this one returns here. Otherwise it returns to the first library screen.
    var staysAsOrigin: Bool {
        switch self {
        case .coverFlow, .albums(.albums), .artists: true
        case .albums(.reorder), .songs, .cd, .album, .device, .settings: false
        }
    }
}

/// The modules' rows in the sidebar's Library section.
struct ModuleLibraryItems: View {
    var body: some View {
        CoverFlowSidebarItem { ModulePage.coverFlow($0) }
        AlbumsSidebarItem { ModulePage.albums($0) }
        ArtistsSidebarItem { ModulePage.artists($0) }
        SongsSidebarItem { ModulePage.songs($0) }
        ImportSidebarItem()
    }
}

/// The modules' sections after the Library section.
struct ModuleSidebarSections: View {
    var body: some View {
        CDSidebarSection { ModulePage.cd($0) }
        DeviceSidebarSection { ModulePage.device($0) }
    }
}

/// Sheets the modules put over the window (`WindowState.Modal.module`).
enum ModuleSheet: Hashable, Sendable {
    case importFiles([URL])
    /// The change list; with `sampleReport`, the report after a write, for screenshots.
    case pendingChanges(sampleReport: Bool)

    /// `--screen pending|write-report`. The sample report shows only while writes are blocked
    /// (demo mode), so it can never stand in for a real one.
    init?(launchName: String, writesBlocked: Bool) {
        switch launchName {
        case "pending": self = .pendingChanges(sampleReport: false)
        case "write-report": self = .pendingChanges(sampleReport: writesBlocked)
        default: return nil
        }
    }

    /// The change list, from the playback bar and `--screen pending`.
    static let changeList: ModuleSheet = .pendingChanges(sampleReport: false)

    /// Add Songs with these files: chosen in the sidebar, ripped from a disc, dropped on the
    /// window or given with `--import`.
    static func addFiles(_ urls: [URL]) -> ModuleSheet { .importFiles(urls) }

    var id: String {
        switch self {
        case .importFiles(let urls): "import:" + urls.map(\.path).joined(separator: "|")
        case .pendingChanges: "pending"
        }
    }

    /// A sheet does not inherit the window's text color; Add Songs sets it, the change list
    /// stays in the system colors.
    @MainActor @ViewBuilder func view(model: LibraryModel) -> some View {
        switch self {
        case .importFiles(let urls):
            ImportSheet(initialURLs: urls).environment(model).foregroundStyle(Theme.fg)
        case .pendingChanges(let sampleReport):
            PendingChangesSheet(report: sampleReport ? .demo : nil)
        }
    }
}

/// The modules' items in the playback bar, after the playback controls.
struct ModuleStatusItems: View {
    var body: some View {
        ChangesStatusItems()
    }
}

/// The modules' items in the File menu.
struct ModuleFileMenuItems: View {
    var body: some View {
        AudioCDMenu()
    }
}

/// The modules' items at the top of the View menu.
struct ModuleViewMenuItems: View {
    var body: some View {
        AlbumsViewMenuItems()
    }
}

/// The app's look: the theme every window shows, and its sections on the Settings page.
/// The only place that knows the themes module - without it, `theme` is
/// `AppTheme.standard`, `settingsSections` is empty, and nothing else changes.
@MainActor
@Observable
final class ModuleAppearance {
    @ObservationIgnored private let themes: ThemeStore

    /// - Parameters:
    ///   - demo: the choice lives in memory and the user's themes in a folder of this
    ///     process, so a demo never changes the user's.
    ///   - launchChoice: `--appearance light|dark|system`, for this process only.
    init(demo: Bool, launchChoice: String?) {
        let folder = demo ? Self.demoThemesFolder : (try? ProductInfo.supportDirectory())?
            .appendingPathComponent("Themes", isDirectory: true)
        themes = ThemeStore(storage: demo ? .memory() : .standard, system: .live(),
                            library: folder.map(ThemeLibrary.init(folder:)),
                            launchChoice: launchChoice.flatMap(ThemeChoice.init(storageValue:)))
    }

    private static var demoThemesFolder: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-demo-themes-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    }

    var theme: AppTheme { themes.current }

    /// The themes module's sections on the Settings page.
    var settingsSections: some View { AppearanceSection(store: themes) }
}

/// What one window keeps for its modules.
@MainActor
final class ModuleStores {
    let cds: AudioCDStore
    let albumOptions: AlbumOptions
    let coverFlow = CoverFlowState()
    let albums = AlbumsState()

    init(launch: LaunchScript) {
        cds = AudioCDStore(services: launch.cdServices)
        albumOptions = AlbumOptions(editorShown: launch.opensAlbumEditor, coverFile: launch.coverFile)
    }

    /// An album that was open stays in the middle of the screen the window goes back to: the wheel
    /// when it was opened there, otherwise Cover Flow.
    func center(_ album: AlbumCard, returningTo origin: ModulePage, in model: LibraryModel) {
        if case .albums = origin {
            albums.center(album, in: albums.shown(from: model.albumsDisplay))
        } else {
            coverFlow.center(album, in: model.coverFlowDisplay)
        }
    }

    /// `--screen <page> --centered N` for a page with its own position: the N-th album on the wheel.
    func center(at index: Int, on page: ModulePage, in model: LibraryModel) {
        if case .albums(.albums) = page, model.albumsDisplay.indices.contains(index) { albums.centered = index }
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

    /// The CD module decides what a mounted or unmounted volume does to the window (`DiscChange`).
    func volumesChanged(inserted: Bool, removed: Bool, window: WindowState, sheetIsOpen: Bool) {
        let shown: URL? = if case .cd(let page) = window.screen { page.volume } else { nil }
        switch DiscChange.after(inserted: inserted, removed: removed, shown: shown, sheetIsOpen: sheetIsOpen, in: cds) {
        case .show(let volume): window.show(ModulePage.disc(volume), animated: true)
        case .showHome: window.showHome(animated: true)
        case .nothing: break
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
            .environment(stores.albums)
            .environment(\.albumsActions, AlbumsActions(
                openAlbum: { window.open($0) },
                done: { window.showHome(animated: true) }))
            .environment(\.coverFlowActions, CoverFlowActions(openAlbum: { window.open($0) }, reorder: reorder))
            .environment(\.cdActions, CDActions(importFiles: { window.addFiles($0) }))
            .environment(\.importActions, ImportActions(addFiles: { window.addFiles($0) }))
            .environment(\.changesActions, ChangesActions(showChanges: { window.show(ModuleSheet.changeList) }))
            .environment(\.artistsActions, ArtistsActions(
                show: { window.show(.artists($0), animated: true) },
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
