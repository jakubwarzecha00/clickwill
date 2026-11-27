import SwiftUI
import ClickwillModel

/// A screen of the Photos module. Its raw value is the name `--screen` takes.
public enum PhotosPage: String, CaseIterable, Hashable, Sendable {
    case photos

    public var title: String { "Photos" }

    /// Shown in the sidebar's Media section (`LibraryModel.showsMedia`); otherwise the window goes back home.
    @MainActor public func isAvailable(in model: LibraryModel) -> Bool { model.showsMedia }
}

/// The Photos row of the sidebar's Media section. The app gives it its selection tag.
public struct PhotosSidebarItem<Tag: Hashable>: View {
    let tag: (PhotosPage) -> Tag

    public init(tag: @escaping (PhotosPage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        Label(PhotosPage.photos.title, systemImage: "photo.on.rectangle")
            .tag(tag(.photos))
    }
}
