import SwiftUI
import ClickwillModel
import ClickwillDevice

/// The screen modules the window shows, and the only file in the app that names them.
///
/// A module is a library of its own (`Sources/<Module>`): it takes shared things from
/// `ClickwillShared` and the model, never from the app or another module. The window knows
/// a module only through `ModulePage`, so removing one means deleting its library and its
/// lines here.
enum ModulePage: Hashable {
    case device(DevicePage)

    /// `--screen <name>`.
    init?(launchName: String) {
        if let page = DevicePage(rawValue: launchName) { self = .device(page); return }
        return nil
    }

    /// The page shown under Diagnostics and Send Diagnostic Report opened from the command line.
    static let diagnosticsBackdrop: ModulePage? = .device(.overview)

    var title: String {
        switch self {
        case .device(let page): page.title
        }
    }

    @MainActor func subtitle(in model: LibraryModel) -> String {
        switch self {
        case .device(let page): page.subtitle(in: model)
        }
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .device(let page): DeviceScreen(page: page)
        }
    }
}

/// The modules' sections at the end of the sidebar.
struct ModuleSidebarSections: View {
    var body: some View {
        DeviceSidebarSection { SidebarItem.module(.device($0)) }
    }
}

extension View {
    /// What the modules ask the window to do, set once around the window's content.
    func moduleActions(window: WindowState, playback: PlaybackController) -> some View {
        environment(\.deviceActions, DeviceActions(
            runDiagnostics: { window.showDiagnostics() },
            sendReport: { window.showSendReport(comment: $0) },
            sendFeedback: { window.showFeedback() },
            stopPlayback: { playback.stop() }))
    }
}
