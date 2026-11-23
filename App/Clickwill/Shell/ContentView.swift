import SwiftUI
import AppKit
import ClickwillModel
import ClickwillShared

/// The library window: the sidebar, the scene with the current screen, the playback bar
/// and what hangs over the window (`WindowState`).
struct ContentView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(DeviceMonitor.self) private var monitor
    @Environment(PlaybackController.self) private var playback
    /// The screen, the album in the middle of the Albums wheel and this window's sheets.
    @State private var window: WindowState
    @State private var modules: ModuleStores
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
        let modules = ModuleStores(launch: launch)
        _modules = State(initialValue: modules)
        _window = State(initialValue: WindowState(model: model, modules: modules))
        _demoHover = State(initialValue: DemoHover(listening: launch.listensForDemoHover))
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
            .onDrop(of: model.isWritable && ModuleSheet.addFiles != nil ? [.fileURL] : [], isTargeted: $dropTargeted) { providers in
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
        .focusedSceneValue(\.window, window)
        .environment(window)
        .modules(modules, window: window, playback: playback)
        .environment(\.demoHover, demoHover.target)
        .onAppear {
            sceneFocused = true
            modules.cds.refresh()
            launch.windowAppeared(window: window, cds: modules.cds)
        }
        .onChange(of: window.screen) { sceneFocused = true }
        .foregroundStyle(Theme.fg)
        // The scene holds the focus, so the window takes the keys and hands them to the page
        // on top (Cover Flow, the Albums wheel). A stage handling them itself would move the
        // artwork even under the album view. Escape goes back where the Back button leads.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in passToModule(press) }
        .onKeyPress(characters: .alphanumerics) { press in passToModule(press) }
        .onKeyPress(.escape) {
            guard !sheetIsOpen else { return .ignored }
            guard window.backTitle != nil else { return .ignored }
            window.goBack()
            return .handled
        }
        // The start screen only once the library is really loaded.
        .onChange(of: model.state) { _, state in
            guard state == .loaded, !launchApplied else { return }
            launchApplied = true
            launch.libraryLoaded(window: window, model: model, modules: modules)
        }
        // The iPod disappeared (`DeviceMonitor` took the library down) - we go back to the first screen.
        .onChange(of: model.source == nil) { _, gone in if gone { window.showHome() } }
        // E.g. Cover Flow once an iPod without it is recognized, after loading or after switching.
        .onChange(of: window.screenIsAvailable) { _, available in
            if !available { window.showHome() }
        }
        .onChange(of: monitor.volumes) { before, now in
            modules.volumesChanged(inserted: !now.subtracting(before).isEmpty, removed: !before.subtracting(now).isEmpty,
                                   window: window, sheetIsOpen: sheetIsOpen)
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

    /// A module page that does not need the library, e.g. a disc in a drive.
    private var standalonePage: ModulePage? {
        window.screen.needsLibrary ? nil : window.screen
    }

    private var title: String {
        if let standalonePage { return standalonePage.windowTitle(in: model, modules: modules) }
        // HIG: we do not title the window with the app name - without a library the title is empty.
        guard model.state == .loaded else { return "" }
        return window.screen.windowTitle(in: model, modules: modules)
    }

    private var subtitle: String {
        if let standalonePage { return standalonePage.subtitle(in: model, modules: modules) }
        guard model.state == .loaded else { return "" }
        return window.screen.subtitle(in: model, modules: modules)
    }

    /// The playback bar at the bottom of the window: when a track was chosen, when playback reported
    /// an error (the message is in the bar - e.g. a track without a file), or when changes are waiting
    /// to be written (from the bar a path leads to their list).
    private var showsPlayer: Bool {
        playback.currentTrack != nil || playback.errorMessage != nil || model.hasPendingChanges
    }

    /// Module screens add their own toolbar items (the disc screen its commands).
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        // Without the sidebar button Cover Flow had no item in the
        // toolbar and the system created no bar - the title and subtitle fell into one
        // gray line in the window bar. A system spacer keeps the bar on every screen.
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        } else {
            ToolbarItem { Spacer() }
        }
        if let backTitle = window.backTitle {
            ToolbarItem(placement: .navigation) {
                Button { window.goBack() } label: { Label(backTitle, systemImage: "chevron.left") }
                    .help("Back to \(backTitle)")
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
    /// go there the same way (`WindowState.addFiles`) as a ripped disc.
    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !sheetIsOpen, model.state == .loaded else { return false }
        Task {
            let urls = await NSItemProvider.fileURLs(from: providers)
            guard !urls.isEmpty else { return }
            window.addFiles(urls)
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

    private func passToModule(_ press: KeyPress) -> KeyPress.Result {
        guard !sheetIsOpen else { return .ignored }
        return window.screen.handle(press, model: model, modules: modules, window: window)
    }

    @ViewBuilder private var content: some View {
        // A disc can be ripped without an iPod - that is even a better order, because a drive
        // and an iPod on one hub can bring down the whole USB tree.
        if let standalonePage {
            standalonePage.screen
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
            window.screen.screen
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
        case .module(let sheet):
            sheet.view.environment(model).foregroundStyle(Theme.fg)
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
