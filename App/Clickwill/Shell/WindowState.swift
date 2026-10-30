import SwiftUI
import Observation
import ClickwillModel

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

    private(set) var screen: Screen = .coverFlow
    /// The album in the middle of Cover Flow - it stays when entering an album and coming back.
    var centered = 0
    /// The album in the middle of the Albums wheel (an index into `albumsDisplay`) - likewise.
    var albumsCentered = 0
    /// The tab the album was opened from - Back returns to it.
    private(set) var albumOrigin: Screen = .coverFlow
    private(set) var modal: Modal?
    /// A request that came while something else hung over the window - e.g. files
    /// from a disc ripped while the change list was open. Shown after it closes.
    @ObservationIgnored private var waiting: Modal?

    @ObservationIgnored private let model: LibraryModel

    init(model: LibraryModel) {
        self.model = model
    }

    // MARK: - Screens

    func show(_ screen: Screen, animated: Bool = false) {
        guard animated else { self.screen = screen; return }
        withAnimation(Theme.screenFade) { self.screen = screen }
    }

    /// The first library screen: Cover Flow, and on an iPod without Cover Flow - Albums.
    var home: Screen { model.hasCoverFlow ? .coverFlow : .albums }

    func showHome(animated: Bool = false) { show(home, animated: animated) }

    func open(_ album: AlbumCard) {
        switch screen {
        case .coverFlow, .albums: albumOrigin = screen
        // From Songs and from the change list we go back to the first library screen.
        default: albumOrigin = home
        }
        show(.album(album), animated: true)
    }

    /// The name of the tab Back returns to.
    var albumOriginTitle: String {
        if case .albums = albumOrigin { "Albums" } else { "Cover Flow" }
    }

    /// Going back from an album to the tab it was opened from - with that album in the middle.
    func closeAlbum(animated: Bool = true) {
        guard case .album(let album) = screen else { return }
        if case .albums = albumOrigin {
            if let index = model.albumsDisplay.firstIndex(where: { $0.id == album.id }) { albumsCentered = index }
        } else if let index = model.coverFlowDisplay.firstIndex(where: { $0.id == album.id }) {
            centered = index
        }
        show(albumOrigin, animated: animated)
    }

    /// From the toolbar and the View menu (HIG: every toolbar item has its counterpart in the menu).
    func showReorder() {
        guard AppFeatures.reorderAlbums, model.state == .loaded else { return }
        show(.reorder, animated: true)
    }

    /// The sidebar selection. An album belongs to the tab it was
    /// opened from, Reorder to Albums.
    var sidebarSelection: SidebarItem? {
        // A disc has its screen even without a loaded iPod.
        if case .audioCD(let volume) = screen { return .disc(volume) }
        guard model.state == .loaded else { return nil }
        switch screen {
        case .coverFlow: return .coverFlow
        case .albums, .reorder: return .albums
        case .album: return albumOrigin == .albums ? .albums : .coverFlow
        case .songs: return .songs
        case .overview: return .overview
        case .backups: return .backups
        case .audioCD: return nil
        }
    }

    func select(_ item: SidebarItem) {
        switch item {
        // Clicking the tab that the open album belongs to leaves the album.
        case .coverFlow:
            if sidebarSelection != .coverFlow { show(.coverFlow) }
        case .albums:
            if sidebarSelection != .albums { show(.albums) }
        case .songs: show(.songs)
        case .overview: show(.overview)
        case .backups: show(.backups)
        case .disc(let volume): show(.audioCD(volume))
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
