import SwiftUI
import ClickwillModel

/// A screen of the Videos module. Its raw value is the name `--screen` takes.
public enum VideosPage: String, CaseIterable, Hashable, Sendable {
    case movies
    case tvShows = "tv-shows"

    public var title: String {
        switch self {
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }

    @MainActor public func subtitle(in model: LibraryModel) -> String {
        switch self {
        case .movies:
            let count = model.videos.movies.count
            return count == 1 ? "1 movie" : "\(count) movies"
        case .tvShows:
            return ""
        }
    }

    /// Shown in the sidebar's Media section (`LibraryModel.showsMedia`); otherwise the window goes back home.
    @MainActor public func isAvailable(in model: LibraryModel) -> Bool { model.showsMedia }

    var systemImage: String {
        switch self {
        case .movies: "film"
        case .tvShows: "tv"
        }
    }
}

/// The Videos rows of the sidebar's Media section. The app gives them their selection tag.
public struct VideosSidebarItems<Tag: Hashable>: View {
    @Environment(LibraryModel.self) private var model
    let tag: (VideosPage) -> Tag

    public init(tag: @escaping (VideosPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        ForEach(VideosPage.allCases, id: \.self) { page in
            Label(page.title, systemImage: page.systemImage)
                .badge(page == .movies ? model.videos.movies.count : 0)
                .tag(tag(page))
        }
    }
}
