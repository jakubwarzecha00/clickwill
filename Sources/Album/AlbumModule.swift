import SwiftUI
import ClickwillModel
import ClickwillShared

/// The album view. It opens over the screen it was opened from, and Back returns there.
public enum AlbumPage: Hashable, Sendable {
    case album(AlbumCard)

    public var album: AlbumCard {
        switch self { case .album(let album): album }
    }

    /// The current card, not the one from the moment of opening, so a rename shows in the window bar.
    @MainActor public func title(in model: LibraryModel) -> String {
        (model.current(album) ?? album).displayTitle
    }

    @MainActor public func subtitle(in model: LibraryModel) -> String {
        (model.current(album) ?? album).displayArtist
    }
}

public struct AlbumModuleScreen: View {
    @Environment(\.albumOptions) private var options
    let page: AlbumPage

    public init(page: AlbumPage) { self.page = page }

    public var body: some View {
        if page.album.isPending {
            PendingAlbumScreen(album: page.album)
        } else {
            AlbumScreen(album: page.album, editorShown: options.editorShown, coverFile: options.coverFile)
        }
    }
}

/// What the album view asks the window and the player to do.
public struct AlbumActions: Sendable {
    public var play: @MainActor @Sendable (_ tracks: [TrackRow], _ startingAt: TrackRow?, _ album: AlbumCard) -> Void
    /// Read while the track list renders, so the playing mark follows the player.
    public var playingTrackID: @MainActor @Sendable () -> TrackRow.ID?
    public var close: @MainActor @Sendable (_ animated: Bool) -> Void

    public init(play: @escaping @MainActor @Sendable (_ tracks: [TrackRow], _ startingAt: TrackRow?, _ album: AlbumCard) -> Void,
                playingTrackID: @escaping @MainActor @Sendable () -> TrackRow.ID?,
                close: @escaping @MainActor @Sendable (_ animated: Bool) -> Void) {
        self.play = play
        self.playingTrackID = playingTrackID
        self.close = close
    }

    static let none = AlbumActions(play: { _, _, _ in }, playingTrackID: { nil }, close: { _ in })
}

/// Launch settings for screenshots and recordings.
public struct AlbumOptions: Sendable {
    /// The edit panel open on arrival.
    public var editorShown: Bool
    /// The image "Change Cover…" takes instead of the file panel, which a recording could not show.
    public var coverFile: URL?

    public init(editorShown: Bool = false, coverFile: URL? = nil) {
        self.editorShown = editorShown
        self.coverFile = coverFile
    }
}

public extension EnvironmentValues {
    @Entry var albumActions: AlbumActions = .none
    @Entry var albumOptions: AlbumOptions = AlbumOptions()
}
