import SwiftUI
import AppKit
import ClickwillModel

/// The library window: the sidebar, the scene with the current screen, the playback bar
/// and what hangs over the window (`WindowState`).
struct ContentView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(DeviceMonitor.self) private var monitor
    @Environment(PlaybackController.self) private var playback
    /// The screen, the album in the middle of Cover Flow and this window's sheets.
    @State private var window: WindowState
    /// Audio CDs in the drive - ripping without Music.
    @State private var cds: AudioCDStore
    @State private var demoHover: DemoHover
    /// A launch for screenshots and recordings: the screen, the album in the middle, the add sheet.
    private let launch: LaunchScript
    /// The width of the panel slid out on the right - the playback bar moves back by it.
    @State private var sidePanel: CGFloat = 0
    /// Files from Finder over the window - highlighting the drop target.
    @State private var dropTargeted = false
    @AppStorage(WelcomeSheet.seenKey) private var welcomeSeen = false
    /// The launch script runs once, on the first load - not after switching iPods.
    @State private var launchApplied = false

    /// Focus on the scene, not on the sidebar - the arrows should scroll
    /// Cover Flow, not the selection in the list on the left.
    @FocusState private var sceneFocused: Bool

    /// The model knows the window state: from it, it knows whether the library is loaded and where
    /// the album being returned from stands.
    init(model: LibraryModel, launch: LaunchScript) {
        _window = State(initialValue: WindowState(model: model))
        _demoHover = State(initialValue: DemoHover(listening: launch.listensForDemoHover))
        _cds = State(initialValue: AudioCDStore(services: launch.cdServices))
        self.launch = launch
    }

    var body: some View {
        // A native macOS 27 window (following Apple's UI Kit): the system sidebar
        // and a toolbar with Liquid Glass. The scene (Cover Flow, the album,
        // the lists) stays ours.
        // The sidebar is permanent and has a fixed width:
        // no hide button, no collapsing and no dragging of the edge -
        // every width change shifted the whole scene sideways.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .fixedSidebarWidth(Theme.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                // Both screens must lie on top of each other, so the old one has time to fade
                // before the new one lights up - hence a ZStack instead of a switch.
                // The transitions are the same crossfade. Carrying the artwork from Cover Flow
                // to its place in the header was tried three times - and every time
                // it jumped somewhere, because the list row with the target artwork is created
                // later than the motion that is supposed to end on it.
                ZStack { content.transition(Theme.screenTransition) }
                // The player only when there is something to play (or something is waiting to be written -
                // from there a path leads to the change list); it slides in from the bottom.
                if showsPlayer {
                    StatusBarView(trailingReserve: sidePanel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.55, bounce: 0.18), value: showsPlayer)
            // The scene reaches under the toolbar and (as a mirror reflection) under the
            // sidebar - the system glass then has something to show through. Our own background
            // ending under the bar gave a flat gray strip (HIG, Toolbars:
            // "reduce the use of toolbar backgrounds").
            .background { Theme.stage.ignoresSafeArea().backgroundExtension() }
            // Files and folders from Finder dropped anywhere on the window open
            // Add Songs with them loaded. The album's track list and the artwork
            // in the Edit panel have their own targets - they lie deeper, so they win.
            .onDrop(of: model.isWritable ? [.fileURL] : [], isTargeted: $dropTargeted) { providers in
                receiveDrop(providers)
            }
            .overlay { if dropTargeted { dropHint } }
            .onPreferenceChange(SidePanelWidthKey.self) { width in sidePanel = width }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbarContent }
            .focusable()
            .focusEffectDisabled()
            .focused($sceneFocused)
        }
        .environment(cds)
        .focusedSceneValue(\.window, window)
        .environment(window)
        .environment(\.demoHover, demoHover.target)
        .onAppear {
            sceneFocused = true
            cds.refresh()
            launch.windowAppeared(window: window, cds: cds)
        }
        .onChange(of: window.screen) { sceneFocused = true }
        .foregroundStyle(Theme.fg)
        // The window handles the arrows and Return, only on the Cover Flow screen or the Albums
        // wheel. The scene would move the artwork even when the album view
        // is on top. Escape in an album goes back to the tab it was opened from.
        .onKeyPress(.leftArrow) { stepCoverFlow(-1) }
        .onKeyPress(.rightArrow) { stepCoverFlow(1) }
        .onKeyPress(.upArrow) { stepAlbums(-1) }
        .onKeyPress(.downArrow) { stepAlbums(1) }
        // A letter from the keyboard - the first album under that letter, like the jump bar on the iPod.
        .onKeyPress(characters: .alphanumerics) { press in jumpAlbums(to: press.characters) }
        .onKeyPress(.return) {
            guard !sheetIsOpen else { return .ignored }
            switch window.screen {
            case .coverFlow where model.coverFlowDisplay.indices.contains(window.centered):
                window.open(model.coverFlowDisplay[window.centered])
            case .albums where model.albumsDisplay.indices.contains(window.albumsCentered):
                window.open(model.albumsDisplay[window.albumsCentered])
            default:
                return .ignored
            }
            return .handled
        }
        .onKeyPress(.escape) {
            guard !sheetIsOpen else { return .ignored }
            switch window.screen {
            case .album:
                window.closeAlbum()
                return .handled
            case .artist:
                window.closeArtist()
                return .handled
            default:
                return .ignored
            }
        }
        // The start screen only once the library is really loaded.
        .onChange(of: model.state) { _, state in
            guard state == .loaded, !launchApplied else { return }
            launchApplied = true
            launch.libraryLoaded(window: window, model: model)
        }
        // The iPod disappeared (`DeviceMonitor` took the library down) - we go back to the first screen.
        .onChange(of: model.source == nil) { _, gone in if gone { window.showHome() } }
        // An iPod without Cover Flow (recognized after loading or after switching) - Albums.
        .onChange(of: model.hasCoverFlow) { _, has in
            if !has, case .coverFlow = window.screen { window.show(.albums) }
        }
        .onChange(of: monitor.volumes) { before, now in
            // An inserted disc: its screen right away, as in Music - unless a sheet
            // hangs over the window or another disc is in progress.
            if !now.subtracting(before).isEmpty, let disc = cds.refresh().first, !sheetIsOpen, cdSession?.isRipping != true {
                window.show(.audioCD(disc.volume), animated: true)
            }
            if !before.subtracting(now).isEmpty {
                cds.refresh()
                if case .audioCD = window.screen, cdSession == nil { window.showHome(animated: true) }
            }
        }
        .sheet(item: Binding(get: { window.modal?.isSheet == true ? window.modal : nil },
                             set: { if $0 == nil { window.closeModal() } }),
               onDismiss: window.modalDidClose) { modal in
            sheet(for: modal)
        }
        // On the first launch, and then from the Help menu. Not on a launch for screenshots or diagnostics.
        .sheet(isPresented: Binding(get: { !welcomeSeen && !launch.isAutomated },
                                    set: { if !$0 { welcomeSeen = true } })) {
            WelcomeSheet()
        }
    }

    // MARK: - Toolbar (native)

    /// The disc session, when its screen is on top.
    private var cdSession: CDSession? {
        if case .audioCD(let volume) = window.screen { return cds.session(volume) }
        return nil
    }

    private var title: String {
        if let cdSession { return cdSession.title }
        // HIG: we do not title the window with the app name - without a library the title is empty.
        guard model.state == .loaded else { return "" }
        switch window.screen {
        case .coverFlow: return "Cover Flow"
        case .albums: return "Albums"
        // The current card, not the one from the moment of opening - otherwise after a rename
        // the window bar kept showing the old one.
        case .album(let album): return (model.current(album) ?? album).displayTitle
        case .reorder: return "Reorder Albums"
        case .songs: return "Songs"
        case .artists: return "Artists"
        case .artist(let artist): return artist
        case .overview: return "Overview"
        case .backups: return "Backups"
        case .audioCD: return ""
        }
    }

    private var subtitle: String {
        if let cdSession {
            return cdSession.draft.albumArtist.isEmpty
                ? "\(cdSession.draft.songs.count) songs · \(AudioCDScreen.time(UInt64(cdSession.disc.duration * 1000)))"
                : cdSession.draft.albumArtist
        }
        guard model.state == .loaded else { return "" }
        switch window.screen {
        // As many albums as the iPod shows - an album scattered across the table is one.
        case .coverFlow, .albums: return "\(model.coverFlowAlbums.count) albums · \(model.trackCount) songs"
        case .album(let album): return (model.current(album) ?? album).displayArtist
        case .reorder: return "The order the iPod shows"
        case .songs: return "\(model.trackCount) songs"
        case .artists: return "\(model.artistCount) artists"
        case .artist(let artist):
            let albumCount = model.albums.filter { $0.displayArtist == artist }.count
            let songCount = model.albums.filter { $0.displayArtist == artist }.reduce(0) { $0 + model.tracks(of: $1).count }
            return "\(albumCount) albums · \(songCount) songs"
        case .overview: return model.deviceName ?? model.source?.displayName ?? ""
        case .backups: return "Restore the iPod to an earlier state"
        case .audioCD: return ""
        }
    }

    /// The playback bar at the bottom of the window: when a track was chosen, when playback reported
    /// an error (the message is in the bar - e.g. a track without a file), or when changes are waiting
    /// to be written (from the bar a path leads to their list).
    private var showsPlayer: Bool {
        playback.currentTrack != nil || playback.errorMessage != nil || model.hasPendingChanges
    }

    /// The disc buttons are added by its screen (`AudioCDScreen`) - they call its commands directly.
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        // Without the sidebar button Cover Flow had no item in the
        // toolbar and the system created no bar - the title and subtitle fell into one
        // gray line in the window bar. A system spacer keeps the bar on every screen.
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem { Spacer() }
        }
        if case .album = window.screen {
            ToolbarItem(placement: .navigation) {
                Button { window.closeAlbum() } label: { Label(window.albumOriginTitle, systemImage: "chevron.left") }
                    .help("Back to \(window.albumOriginTitle)")
            }
        }
        if case .artist = window.screen {
            ToolbarItem(placement: .navigation) {
                Button { window.closeArtist() } label: { Label("Artists", systemImage: "chevron.left") }
                    .help("Back to Artists")
            }
        }
        if AppFeatures.reorderAlbums, model.state == .loaded, case .coverFlow = window.screen {
            ToolbarItem(placement: .primaryAction) {
                // The symbol alone, without a label: the HIG says not to mix text and icons on
                // a shared background. The name stays for VoiceOver and in the tooltip.
                Button(action: window.showReorder) { Label("Reorder Albums", systemImage: "arrow.up.arrow.down") }
                    .help("Reorder Albums")
            }
        }
        if case .reorder = window.screen {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { window.showHome(animated: true) }
                    .prominentGlassButtonStyle()
            }
        }
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Theme.accent, lineWidth: 2)
            .padding(8)
            .overlay {
                Label("Drop to Add Songs", systemImage: "plus.circle")
                    .font(.theme(.row, weight: .medium)).hintChip()
            }
            .allowsHitTesting(false)
    }

    /// The same dialog and duplicate check as "Add Songs or Albums" - the files
    /// go there the same way (`WindowState.showImport`) as a ripped disc.
    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !sheetIsOpen, model.state == .loaded else { return false }
        Task {
            let urls = await NSItemProvider.fileURLs(from: providers)
            guard !urls.isEmpty else { return }
            window.showImport(urls)
        }
        return true
    }

    /// Whether a sheet hangs over the window. The keys then belong to it, not to the scene
    /// underneath - otherwise the arrows scrolled Cover Flow behind the
    /// "Add songs" sheet, and Escape closed the album in the background instead of the sheet.
    ///
    /// We check the app's windows, not `WindowState.modal`: screens have
    /// their own sheets too (missing files in an album, the welcome). A forgotten
    /// sheet would bring the same bug back.
    private var sheetIsOpen: Bool {
        NSApp.windows.contains { $0.isSheet && $0.isVisible }
    }

    private func stepCoverFlow(_ delta: Int) -> KeyPress.Result {
        guard !sheetIsOpen else { return .ignored }
        guard case .coverFlow = window.screen, !model.coverFlowDisplay.isEmpty else { return .ignored }
        let target = min(model.coverFlowDisplay.count - 1, max(0, window.centered + delta))
        if target != window.centered {
            withAnimation(.spring(duration: 0.32, bounce: 0.12)) { window.centered = target }
        }
        return .handled
    }

    private func stepAlbums(_ delta: Int) -> KeyPress.Result {
        guard !sheetIsOpen else { return .ignored }
        guard case .albums = window.screen, !model.albumsDisplay.isEmpty else { return .ignored }
        let target = min(model.albumsDisplay.count - 1, max(0, window.albumsCentered + delta))
        if target != window.albumsCentered {
            withAnimation(.spring(duration: 0.32, bounce: 0.12)) { window.albumsCentered = target }
        }
        return .handled
    }

    /// A digit and any other script stand under `#` on the iPod.
    private func jumpAlbums(to characters: String) -> KeyPress.Result {
        guard !sheetIsOpen, case .albums = window.screen, let typed = characters.first else { return .ignored }
        let letter = typed.isASCII && typed.isLetter ? typed.uppercased() : "#"
        guard let index = model.albumsDisplay.firstIndex(where: { model.menuLetter(of: $0) == letter }) else { return .ignored }
        withAnimation(.spring(duration: 0.32, bounce: 0.12)) { window.albumsCentered = index }
        return .handled
    }

    @ViewBuilder private var content: some View {
        // A disc can be ripped without an iPod - that is even a better order, because a drive
        // and an iPod on one hub can bring down the whole USB tree.
        if let cdSession {
            AudioCDScreen(session: cdSession).id(cdSession.disc.volume)
        } else {
            libraryContent
        }
    }

    @ViewBuilder private var libraryContent: some View {
        switch model.state {
        case .loading:
            EmptyStateView(text: "Reading Your iPod…",
                           detail: "This can take a moment on a full library. Keep the iPod plugged in until it finishes.",
                           busy: true)
        case .empty:
            EmptyStateView(text: "No iPod Connected",
                           detail: "Connect an iPod classic or iPod nano to this Mac. Clickwill finds it on its own.")
        case .failed(let failure):
            EmptyStateView(text: "Clickwill Couldn't Read This iPod's Library", detail: ErrorPresenter.message(for: failure))
        case .loaded:
            switch window.screen {
            case .coverFlow:
                CoverFlowScreen(centered: $window.centered, open: window.open)
            case .albums:
                AlbumWheelScreen(centered: $window.albumsCentered, open: window.open)
            case .album(let album):
                if album.isPending {
                    PendingAlbumScreen(album: album, onClose: { window.closeAlbum() })
                } else {
                    AlbumScreen(album: album, editorShown: launch.opensAlbumEditor, coverFile: launch.coverFile,
                                onDeleted: { window.closeAlbum(animated: false) })
                }
            case .reorder:
                ReorderScreen()
            case .songs:
                SongsScreen(openAlbum: window.open)
            case .artists:
                ArtistsScreen(openAlbum: window.open)
            case .artist(let artist):
                ArtistDetailScreen(artist: artist, openAlbum: window.open)
            case .overview:
                OverviewScreen()
            case .backups:
                BackupsScreen()
            case .audioCD:
                EmptyStateView(text: "The CD Was Ejected", detail: "Insert it again to import its songs.")
            }
        }
    }

    /// A sheet does not inherit the window's text color (the `.foregroundStyle` above
    /// applies to the scene) - adding, feedback and About set it explicitly, as when
    /// reviewing the screens. The change list stays in the system colors.
    @ViewBuilder private func sheet(for modal: WindowState.Modal) -> some View {
        switch modal {
        case .pending:
            PendingChangesSheet(report: launch.sampleWriteReport(writesBlocked: model.writesBlocked))
                .onAppear { model.refreshPreflight() }
        case .importFiles(let urls):
            ImportSheet(initialURLs: urls).environment(model).foregroundStyle(Theme.fg)
        case .feedback:
            FeedbackSheet().environment(model).foregroundStyle(Theme.fg)
        case .about:
            AboutView().foregroundStyle(Theme.fg)
        case .diagnostics(let send):
            DiagnosticsSheet(sendComment: send).environment(model).environment(window)
                .environment(\.sampleDiagnostics, launch.sampleDiagnostics).foregroundStyle(Theme.fg)
        case .rockboxReport:
            RockboxReportSheet().environment(model).environment(\.sampleDiagnostics, launch.sampleDiagnostics).foregroundStyle(Theme.fg)
        case .switchConfirmation:
            // A question, not a sheet - the iPod card shows it (`DeviceCard`).
            EmptyView()
        }
    }
}
