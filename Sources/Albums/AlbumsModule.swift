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

/// One window's position on the wheel. It outlives the screen, so an album opened from the wheel
/// returns to the same place.
@MainActor
@Observable
public final class AlbumsState {
    /// An index into `LibraryModel.albumsDisplay`.
    public var centered = 0

    public init() {}

    public func center(_ album: AlbumCard, in albums: [AlbumCard]) {
        if let index = albums.firstIndex(where: { $0.id == album.id }) { centered = index }
    }

    /// Up and down turn the wheel, Return opens the album in the middle, and a letter or digit
    /// jumps to the first album under it, like the iPod's jump bar. Digits and other scripts
    /// stand under "#", as on the iPod.
    public func handle(_ key: KeyEquivalent, characters: String, albums: [AlbumCard],
                       letter: (AlbumCard) -> String, open: (AlbumCard) -> Void) -> KeyPress.Result {
        switch key {
        case .upArrow, .downArrow:
            guard !albums.isEmpty else { return .ignored }
            move(to: centered + (key == .upArrow ? -1 : 1), count: albums.count)
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
            AlbumWheelScreen(centered: $state.centered, open: actions.openAlbum)
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
