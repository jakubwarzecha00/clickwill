import SwiftUI
import ClickwillModel

/// A screen of the Artists module.
public enum ArtistsPage: Hashable, Sendable {
    case list
    case artist(String)

    /// `--screen artists`.
    public init?(launchName: String) {
        guard launchName == "artists" else { return nil }
        self = .list
    }

    public var title: String {
        switch self {
        case .list: "Artists"
        case .artist(let artist): artist
        }
    }

    @MainActor public func subtitle(in model: LibraryModel) -> String {
        switch self {
        case .list:
            return Self.count(model.artistCount, "artist")
        case .artist(let artist):
            let albums = model.albums.filter { $0.displayArtist == artist }
            let songs = albums.reduce(0) { $0 + model.tracks(of: $1).count }
            return "\(Self.count(albums.count, "album")) · \(Self.count(songs, "song"))"
        }
    }

    /// Where Back and Escape lead.
    public var parent: ArtistsPage? {
        if case .artist = self { .list } else { nil }
    }

    private static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(number == 1 ? noun : noun + "s")"
    }
}

public struct ArtistsScreen: View {
    let page: ArtistsPage

    public init(page: ArtistsPage) {
        self.page = page
    }

    public var body: some View {
        switch page {
        case .list: ArtistListScreen()
        case .artist(let artist): ArtistDetailScreen(artist: artist)
        }
    }
}

/// The Artists row of the sidebar's Library section. The app gives it its selection tag.
public struct ArtistsSidebarItem<Tag: Hashable>: View {
    @Environment(LibraryModel.self) private var model
    let tag: (ArtistsPage) -> Tag

    public init(tag: @escaping (ArtistsPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        let loaded = model.state == .loaded
        Label("Artists", systemImage: "person.2")
            .badge(loaded ? model.artistCount : 0)
            .tag(tag(.list))
            .disabled(!loaded)
    }
}

/// What the Artists screens ask the app to do; set by the app in `App/Clickwill/Shell/Modules.swift`.
public struct ArtistsActions: Sendable {
    public var show: @MainActor @Sendable (ArtistsPage) -> Void
    public var openAlbum: @MainActor @Sendable (AlbumCard) -> Void

    public init(show: @escaping @MainActor @Sendable (ArtistsPage) -> Void,
                openAlbum: @escaping @MainActor @Sendable (AlbumCard) -> Void) {
        self.show = show
        self.openAlbum = openAlbum
    }

    static let none = ArtistsActions(show: { _ in }, openAlbum: { _ in })
}

public extension EnvironmentValues {
    @Entry var artistsActions: ArtistsActions = .none
}
