import SwiftUI
import ClickwillModel

/// A screen of the Podcasts module. Its raw value is the name `--screen` takes.
public enum PodcastsPage: String, CaseIterable, Hashable, Sendable {
    case podcasts

    public var title: String { "Podcasts" }

    /// Shown in the sidebar's Media section (`LibraryModel.showsMedia`); otherwise the window goes back home.
    @MainActor public func isAvailable(in model: LibraryModel) -> Bool { model.showsMedia }
}

/// The Podcasts row of the sidebar's Media section. The app gives it its selection tag.
public struct PodcastsSidebarItem<Tag: Hashable>: View {
    let tag: (PodcastsPage) -> Tag

    public init(tag: @escaping (PodcastsPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        Label(PodcastsPage.podcasts.title, systemImage: "antenna.radiowaves.left.and.right")
            .tag(tag(.podcasts))
    }
}
