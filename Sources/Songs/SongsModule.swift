import SwiftUI
import ClickwillModel

/// A screen of the Songs module. Its raw value is the name `--screen` takes.
public enum SongsPage: String, CaseIterable, Hashable, Sendable {
    case songs

    public var title: String { "Songs" }

    @MainActor public func subtitle(in model: LibraryModel) -> String {
        model.trackCount == 1 ? "1 song" : "\(model.trackCount) songs"
    }
}

/// The Songs row of the sidebar's Library section. The app gives it its selection tag.
public struct SongsSidebarItem<Tag: Hashable>: View {
    @Environment(LibraryModel.self) private var model
    let tag: (SongsPage) -> Tag

    public init(tag: @escaping (SongsPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        let loaded = model.state == .loaded
        Label(SongsPage.songs.title, systemImage: "music.note")
            .badge(loaded ? model.trackCount : 0)
            .tag(tag(.songs))
            .disabled(!loaded)
    }
}

/// What the Songs screen asks the app to do; set by the app in `App/Clickwill/Shell/Modules.swift`.
public struct SongsActions: Sendable {
    public var play: @MainActor @Sendable (_ tracks: [TrackRow], _ startingAt: TrackRow?, _ album: AlbumCard) -> Void
    public var openAlbum: @MainActor @Sendable (AlbumCard) -> Void

    public init(play: @escaping @MainActor @Sendable (_ tracks: [TrackRow], _ startingAt: TrackRow?, _ album: AlbumCard) -> Void,
                openAlbum: @escaping @MainActor @Sendable (AlbumCard) -> Void) {
        self.play = play
        self.openAlbum = openAlbum
    }

    static let none = SongsActions(play: { _, _, _ in }, openAlbum: { _ in })
}

public extension EnvironmentValues {
    @Entry var songsActions: SongsActions = .none
}
