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
        /// A module's sheet, e.g. Add Songs (`ModuleSheet`).
        case module(ModuleSheet)
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
            case .module(let sheet): sheet.id
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

    /// The module page on top (`Modules.swift`).
    private(set) var screen: ModulePage
    /// The page a page that opens over (an album) was opened from; Back returns to it.
    private(set) var origin: ModulePage
    private(set) var modal: Modal?
    /// A request that came while something else hung over the window - e.g. files
    /// from a disc ripped while the change list was open. Shown after it closes.
    @ObservationIgnored private var waiting: Modal?

    @ObservationIgnored private let model: LibraryModel
    @ObservationIgnored private let modules: ModuleStores

    init(model: LibraryModel, modules: ModuleStores) {
        self.model = model
        self.modules = modules
        screen = ModulePage.start
        origin = ModulePage.start
    }

    // MARK: - Screens

    func show(_ page: ModulePage, animated: Bool = false) {
        guard animated else { screen = page; return }
        withAnimation(Theme.screenFade) { screen = page }
    }

    /// The first library screen: Cover Flow, and on an iPod without Cover Flow, Albums.
    var home: ModulePage { ModulePage.home(in: model) }

    /// False once the shown page stops fitting the loaded iPod; the window then goes home.
    var screenIsAvailable: Bool { screen.isAvailable(in: model) }

    func showHome(animated: Bool = false) { show(home, animated: animated) }

    func open(_ album: AlbumCard) {
        guard let page = ModulePage.album(album) else { return }
        // From Songs and from the change list we go back to the first library screen.
        origin = screen.staysAsOrigin ? screen : home
        show(page, animated: true)
    }

    /// The name on the Back button, or nil when the screen has nowhere to go back to.
    var backTitle: String? {
        if let parent = screen.parent { return parent.title }
        return screen.opensOver ? origin.root.title : nil
    }

    /// Back from a page opened over another screen, with the album it showed in the middle there.
    func closeOver(animated: Bool = true) {
        guard screen.opensOver else { return }
        if let album = screen.shownAlbum { modules.center(album, returningTo: origin, in: model) }
        show(origin, animated: animated)
    }

    /// Back from a module page: to its parent (an artist to Artists), or to the screen it opened over.
    func goBack(animated: Bool = true) {
        if let parent = screen.parent {
            show(parent, animated: animated)
        } else {
            closeOver(animated: animated)
        }
    }

    /// From the toolbar and the View menu (HIG: every toolbar item has its counterpart in the menu).
    func showReorder() {
        guard AppFeatures.reorderAlbums, model.state == .loaded, let page = ModulePage.reorder else { return }
        show(page, animated: true)
    }

    /// The selected sidebar row. A page opened over another screen (an album) belongs to that
    /// screen's row, Reorder to Albums.
    var sidebarSelection: ModulePage? {
        if !screen.needsLibrary { return screen.root }
        guard model.state == .loaded else { return nil }
        return screen.opensOver ? origin.root : screen.root
    }

    /// Clicking the row the open album belongs to keeps the album open.
    func select(_ row: ModulePage) {
        if sidebarSelection != row { show(row) }
    }

    // MARK: - Over the window

    func show(_ sheet: ModuleSheet) { present(.module(sheet)) }

    /// Add Songs with these files, when a module adds songs.
    func addFiles(_ urls: [URL]) {
        guard !urls.isEmpty, let sheet = ModuleSheet.addFiles?(urls) else { return }
        present(.module(sheet))
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
