import SwiftUI
import ClickwillModel
import ClickwillShared

/// The Albums tab and Reorder, which belongs to it in the sidebar. Raw values are the names
/// `--screen` takes.
public enum AlbumsPage: String, CaseIterable, Hashable, Sendable {
    case albums
    case reorder

    public var title: String {
        switch self {
        case .albums: "Albums"
        case .reorder: "Reorder Albums"
        }
    }

    @MainActor public func subtitle(in model: LibraryModel) -> String {
        switch self {
        // As many albums as the iPod shows, the same count as Cover Flow.
        case .albums: "\(pluralized(model.coverFlowAlbums.count, "album")) · \(pluralized(model.trackCount, "song"))"
        case .reorder: "The order the iPod shows"
        }
    }

    /// The page whose sidebar row is selected. Reorder has no Back button, only Done.
    public var sidebarPage: AlbumsPage { .albums }
}

/// How the Albums tab lays albums out. The choice is remembered between launches.
public enum AlbumsLayout: String, CaseIterable, Sendable {
    case wheel
    case grid

    static let defaultsKey = "albumsLayout"

    var title: String {
        switch self {
        case .wheel: "Wheel"
        case .grid: "Grid"
        }
    }

    var symbol: String {
        switch self {
        case .wheel: "rectangle.stack"
        case .grid: "square.grid.2x2"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .wheel: "1"
        case .grid: "2"
        }
    }
}

/// One window's position on the wheel or in the grid. It outlives the screen, so an album opened from the wheel
/// returns to the same place.
@MainActor
@Observable
public final class AlbumsState {
    /// An index into `LibraryModel.albumsDisplay`: the middle of the wheel, the selection in the grid.
    public var centered = 0
    public var layout: AlbumsLayout {
        didSet { defaults.set(layout.rawValue, forKey: AlbumsLayout.defaultsKey) }
    }
    /// Set by the grid as the window's width changes; Up and Down move by a whole row.
    var gridColumns = 1
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = defaults.string(forKey: AlbumsLayout.defaultsKey).flatMap(AlbumsLayout.init) ?? .wheel
    }

    public func center(_ album: AlbumCard, in albums: [AlbumCard]) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) { centered = index }
    }

    /// Up and down turn the wheel; in the grid the arrows move the selection by an album or a row.
    /// Return opens the selected album, and a letter or digit jumps to the first album under it,
    /// like the iPod's jump bar. Digits and other scripts stand under "#", as on the iPod.
    public func handle(_ key: KeyEquivalent, characters: String, albums: [AlbumCard],
                       letter: (AlbumCard) -> String, open: (AlbumCard) -> Void) -> KeyPress.Result {
        switch key {
        case .upArrow, .downArrow:
            guard !albums.isEmpty else { return .ignored }
            let up = key == .upArrow
            switch layout {
            case .wheel: move(to: centered + (up ? -1 : 1), count: albums.count)
            case .grid: move(to: Self.rowNeighbor(of: centered, up: up, columns: gridColumns, count: albums.count),
                             count: albums.count)
            }
            return .handled
        case .leftArrow, .rightArrow:
            guard layout == .grid, !albums.isEmpty else { return .ignored }
            move(to: centered + (key == .leftArrow ? -1 : 1), count: albums.count)
            return .handled
        case .return:
            guard albums.indices.contains(centered) else { return .ignored }
            open(albums[centered])
            return .handled
        default:
            guard let typed = characters.first,
                  typed.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) else { return .ignored }
            let wanted = typed.isASCII && typed.isLetter ? typed.uppercased() : "#"
            guard let index = albums.firstIndex(where: { letter($0) == wanted }) else { return .ignored }
            withAnimation(.spring(duration: 0.32, bounce: 0.12)) { centered = index }
            return .handled
        }
    }

    /// The album above or below in the grid. Down from a row above a shorter last row goes to the
    /// last album, as in Finder; past the first or the last row the selection stays.
    nonisolated static func rowNeighbor(of index: Int, up: Bool, columns: Int, count: Int) -> Int {
        let columns = max(1, columns)
        if up { return index - columns >= 0 ? index - columns : index }
        if index + columns < count { return index + columns }
        let lastRow = (count - 1) / columns
        return index / columns < lastRow ? count - 1 : index
    }

    private func move(to index: Int, count: Int) {
        let target = min(count - 1, max(0, index))
        if target != centered {
            withAnimation(.spring(duration: 0.32, bounce: 0.12)) { centered = target }
        }
    }
}

public struct AlbumsScreen: View {
    @Environment(AlbumsState.self) private var state
    @Environment(\.albumsActions) private var actions
    let page: AlbumsPage

    public init(page: AlbumsPage) { self.page = page }

    public var body: some View {
        @Bindable var state = state
        switch page {
        case .albums:
            Group {
                switch state.layout {
                case .wheel: AlbumWheelScreen(centered: $state.centered, open: actions.openAlbum)
                case .grid: AlbumGridScreen(selected: $state.centered, columns: $state.gridColumns,
                                            open: actions.openAlbum)
                }
            }
            .toolbar {
                ToolbarItem {
                    Picker("View", selection: $state.layout) {
                        ForEach(AlbumsLayout.allCases, id: \.self) { layout in
                            Label(layout.title, systemImage: layout.symbol).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                    .help("Show albums on a wheel or in a grid")
                    .accessibilityIdentifier("albums.layout")
                }
            }
            .focusedSceneValue(\.albumsState, state)
        case .reorder:
            ReorderScreen()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { actions.done() }
                            .prominentGlassButtonStyle()
                    }
                }
        }
    }
}

/// The Albums row of the sidebar's Library section. The app gives it its selection tag.
public struct AlbumsSidebarItem<Tag: Hashable>: View {
    @Environment(LibraryModel.self) private var model
    let tag: (AlbumsPage) -> Tag

    public init(tag: @escaping (AlbumsPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        let loaded = model.state == .loaded
        Label(AlbumsPage.albums.title, systemImage: "square.stack")
            .badge(loaded ? model.albumsDisplay.count : 0)
            .tag(tag(.albums))
            .disabled(!loaded)
    }
}

/// "as Wheel" and "as Grid" in the View menu, enabled while the Albums tab is shown.
public struct AlbumsViewMenuItems: View {
    @FocusedValue(\.albumsState) private var state

    public init() {}

    public var body: some View {
        ForEach(AlbumsLayout.allCases, id: \.self) { layout in
            Toggle("as \(layout.title)", isOn: Binding(get: { state?.layout == layout },
                                                       set: { if $0 { state?.layout = layout } }))
                .keyboardShortcut(layout.shortcut, modifiers: .command)
        }
        .disabled(state == nil)
    }
}

struct AlbumsStateKey: FocusedValueKey { typealias Value = AlbumsState }

extension FocusedValues {
    /// The shown Albums tab's state, for the View menu.
    var albumsState: AlbumsState? {
        get { self[AlbumsStateKey.self] }
        set { self[AlbumsStateKey.self] = newValue }
    }
}

/// What the Albums pages ask the window to do.
public struct AlbumsActions: Sendable {
    public var openAlbum: @MainActor @Sendable (AlbumCard) -> Void
    /// Reorder's Done.
    public var done: @MainActor @Sendable () -> Void

    public init(openAlbum: @escaping @MainActor @Sendable (AlbumCard) -> Void,
                done: @escaping @MainActor @Sendable () -> Void) {
        self.openAlbum = openAlbum
        self.done = done
    }

    static let none = AlbumsActions(openAlbum: { _ in }, done: {})
}

public extension EnvironmentValues {
    @Entry var albumsActions: AlbumsActions = .none
}
