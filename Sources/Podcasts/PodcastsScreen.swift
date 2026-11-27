import SwiftUI
import ClickwillModel
import ClickwillShared

/// Podcasts are not measured yet, so the page can only say whether anything is left unsorted.
public struct PodcastsScreen: View {
    @Environment(LibraryModel.self) private var model

    public init() {}

    public var body: some View {
        EmptyStateView.unsortedMedia(none: "No Podcasts on This iPod", unrecognized: model.videos.unrecognizedCount)
    }
}
