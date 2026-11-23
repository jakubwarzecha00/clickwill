import SwiftUI
import ClickwillModel

/// A screen of the sidebar's Device section. Its raw value is the name `--screen` takes.
public enum DevicePage: String, CaseIterable, Hashable, Sendable {
    case overview
    case backups

    /// The window title on this screen.
    public var title: String {
        switch self {
        case .overview: "Overview"
        case .backups: "Backups"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "info.circle"
        case .backups: "clock.arrow.circlepath"
        }
    }

    /// The line under the window title.
    @MainActor public func subtitle(in model: LibraryModel) -> String {
        switch self {
        case .overview: model.deviceName ?? model.source?.displayName ?? ""
        case .backups: "Restore the iPod to an earlier state"
        }
    }
}

/// The screen of a Device page.
public struct DeviceScreen: View {
    let page: DevicePage

    public init(page: DevicePage) {
        self.page = page
    }

    public var body: some View {
        switch page {
        case .overview: OverviewScreen()
        case .backups: BackupsScreen()
        }
    }
}

/// The Device section of the sidebar. The app gives each page its own selection tag.
public struct DeviceSidebarSection<Tag: Hashable>: View {
    @Environment(LibraryModel.self) private var model
    let tag: (DevicePage) -> Tag

    public init(tag: @escaping (DevicePage) -> Tag) {
        self.tag = tag
    }

    public var body: some View {
        let loaded = model.state == .loaded
        Section("Device") {
            label(.overview)
                .disabled(!loaded)
            // Backups were made on every write, and there was no way to use them
            // outside the command line.
            label(.backups)
                .disabled(!loaded || model.device == nil)
                .help(model.device == nil ? "Backups belong to a connected iPod." : "")
        }
    }

    private func label(_ page: DevicePage) -> some View {
        Label(page.title, systemImage: page.systemImage).tag(tag(page))
    }
}
