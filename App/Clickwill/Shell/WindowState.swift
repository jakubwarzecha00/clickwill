import SwiftUI
import Observation
import ClickwillModel
import ClickwillShared

/// The state of one window: the screen on top, the albums in the middle of Cover Flow and of the Albums
/// wheel, and what hangs over the window. Views, menus and panels call its
/// methods instead of sending each other events - the state is also seen by a view that appears
/// later, and two requests in one tick do not merge into one.
///
/// One per window (`ContentView`). Views take it from the environment, menus through
/// `@FocusedValue(\.window)` - a command reaches the active window.
@MainActor
@Observable
final class WindowState {

    /// What hangs over the window - at most one thing at a time.
    enum Modal: Identifiable, Equatable {
        /// The change list (after a write - the report).
        case pending
        /// The add sheet with these files: chosen in a panel, dropped
        /// on the window or ripped from a disc.
        case importFiles([URL])
        case feedback
        case about
        /// Diagnostics of the loaded iPod (`DiagnosticsSheet`); with a comment, Send Diagnostic
        /// Report opens over it straight away, the comment filled in.
        case diagnostics(send: String?)
        /// How the library looks in Rockbox (`RockboxReportSheet`).
        case rockboxReport
        /// The question about discarding unsaved changes before loading another iPod.
        case switchConfirmation(IPodChoice)

        var id: String {
            switch self {
            case .pending: "pending"
            case .importFiles(let urls): "import:" + urls.map(\.path).joined(separator: "|")
            case .feedback: "feedback"
            case .about: "about"
            case .diagnostics: "diagnostics"
            case .rockboxReport: "rockbox"
            case .switchConfirmation(let choice): "switch:" + choice.id
            }
        }

        /// A sheet, not a question (`alert`).
        var isSheet: Bool {
            if case .switchConfirmation = self { false } else { true }
        }
    }

    private(set) var screen: Screen
    /// The album in the middle of the Albums wheel (an index into `albumsDisplay`) - likewise.
    var albumsCentered = 0
    /// The screen a page that opens over (an album) was opened from; Back returns to it.
    private(set) var origin: Screen
    private(set) var modal: Modal?
    /// A request that came while something else hung over the window - e.g. files
    /// from a disc ripped while the change list was open. Shown after it closes.
    @ObservationIgnored private var waiting: Modal?

    @ObservationIgnored private let model: LibraryModel
    @ObservationIgnored private let modules: ModuleStores

    init(model: LibraryModel, modules: ModuleStores) {
        self.model = model
        self.modules = modules
        let start = ModulePage.start.map(Screen.module) ?? .albums
        screen = start
        origin = start
    }

    // MARK: - Screens

    func show(_ screen: Screen, animated: Bool = false) {
        guard animated else { self.screen = screen; return }
        withAnimation(Theme.screenFade) { self.screen = screen }
    }

    /// The first library screen: Cover Flow, and on an iPod without Cover Flow, Albums.
    var home: Screen { ModulePage.home(in: model).map(Screen.module) ?? .albums }

    /// False once the shown page stops fitting the loaded iPod; the window then goes home.
    var screenIsAvailable: Bool {
        if case .module(let page) = screen { page.isAvailable(in: model) } else { true }
    }

    func showHome(animated: Bool = false) { show(home, animated: animated) }

    func open(_ album: AlbumCard) {
        guard let page = ModulePage.album(album) else { return }
        switch screen {
        case .albums: origin = screen
        case .module(let current) where current.staysAsOrigin: origin = screen
        // From Songs and from the change list we go back to the first library screen.
        default: origin = home
        }
        show(.module(page), animated: true)
    }

    /// The name on the Back button, or nil when the screen has nowhere to go back to.
    var backTitle: String? {
        guard case .module(let page) = screen else { return nil }
        if let parent = page.parent { return parent.title }
        guard page.opensOver else { return nil }
        if case .module(let page) = origin { return page.root.title }
        return "Albums"
    }

    /// Back from a page opened over another screen, with the album it showed in the middle there.
    func closeOver(animated: Bool = true) {
        guard case .module(let page) = screen, page.opensOver else { return }
        if let album = page.shownAlbum {
            if case .albums = origin {
                if let index = model.albumsDisplay.firstIndex(where: { $0.id == album.id }) { albumsCentered = index }
            } else {
                modules.center(album, in: model)
            }
        }
        show(origin, animated: animated)
    }

    /// Back from a module page: to its parent (an artist to Artists), or to the screen it opened over.
    func goBack(animated: Bool = true) {
        guard case .module(let page) = screen else { return }
        if let parent = page.parent {
            show(.module(parent), animated: animated)
        } else {
            closeOver(animated: animated)
        }
    }

    /// From the toolbar and the View menu (HIG: every toolbar item has its counterpart in the menu).
    func showReorder() {
        guard AppFeatures.reorderAlbums, model.state == .loaded else { return }
        show(.reorder, animated: true)
    }

    /// The sidebar selection. A page opened over another screen (an album) belongs to that
    /// screen's tab, Reorder to Albums.
    var sidebarSelection: SidebarItem? {
        if case .module(let page) = screen, !page.needsLibrary { return .module(page.root) }
        guard model.state == .loaded else { return nil }
        switch screen {
        case .albums, .reorder: return .albums
        case .module(let page) where page.opensOver:
            if case .albums = origin { return .albums }
            if case .module(let page) = origin { return .module(page.root) }
            return nil
        case .module(let page): return .module(page.root)
        }
    }

    func select(_ item: SidebarItem) {
        switch item {
        // Clicking the tab that the open album belongs to keeps the album open.
        case .albums:
            if sidebarSelection != .albums { show(.albums) }
        case .module(let page):
            if sidebarSelection != item { show(.module(page)) }
        }
    }

    // MARK: - Over the window

    func showPending() { present(.pending) }

    func showImport(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        present(.importFiles(urls))
    }

    func showFeedback() { present(.feedback) }

    func showAbout() { present(.about) }

    func showDiagnostics() { present(.diagnostics(send: nil)) }

    /// Diagnostics with Send Diagnostic Report over it - from the Help menu, Overview and
    /// the question after an experimental write.
    func showSendReport(comment: String = "") { present(.diagnostics(send: comment)) }

    func showRockboxReport() { present(.rockboxReport) }

    func confirmSwitch(to choice: IPodChoice) { present(.switchConfirmation(choice)) }

    /// The chosen iPod waiting for consent to discard the changes.
    var switchCandidate: IPodChoice? {
        if case .switchConfirmation(let choice) = modal { choice } else { nil }
    }

    /// Closing by the user (a button in the sheet, Escape, a button of the question).
    func closeModal() { modal = nil }

    /// After a sheet or a question disappears - only then can the next one be
    /// shown, because of two at once the system shows one.
    func modalDidClose() {
        guard modal == nil, let next = waiting else { return }
        waiting = nil
        modal = next
    }

    private func present(_ request: Modal) {
        guard request != modal else { return }
        if modal == nil { modal = request } else { waiting = request }
    }
}

struct WindowStateKey: FocusedValueKey { typealias Value = WindowState }

extension FocusedValues {
    /// The state of the active window - for menu commands.
    var window: WindowState? {
        get { self[WindowStateKey.self] }
        set { self[WindowStateKey.self] = newValue }
    }
}
