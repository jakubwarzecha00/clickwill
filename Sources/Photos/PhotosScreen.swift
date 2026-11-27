import SwiftUI
import ClickwillModel
import ClickwillShared

/// What the iPod holds in photos. Clickwill does not read the photo library yet, so the page
/// says only whether there is one.
public struct PhotosScreen: View {
    @Environment(LibraryModel.self) private var model

    public init() {}

    public var body: some View {
        switch model.photos {
        case .none:
            EmptyStateView(text: "No Photos on This iPod")
        case .present:
            EmptyStateView(text: "Your iPod Has Photos",
                           detail: "I can't show them yet. They stay on your iPod untouched.")
        case .notInBackup:
            EmptyStateView(text: "This Backup Has No Photos",
                           detail: "Backups keep your library and artwork, not photos.")
        }
    }
}
