import SwiftUI
import ClickwillModel
import ClickwillShared

/// The sidebar: the iPod card, the library, discs in the drive, the device,
/// and at the bottom feedback and About.
struct SidebarView: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        // The iPod in a separate bubble above the list, as in the first design: it is
        // the starting point, not one of the navigation items. On macOS 26+ in the strip
        // above the list (the bar's glass shows through under it).
        if Self.cardInList {
            navigation
        } else {
            navigation.safeAreaInset(edge: .top, spacing: 0) { DeviceCard() }
        }
    }

    /// On macOS 14-25 a card above the list - in a `safeAreaInset` strip or in a `VStack` -
    /// squeezed the list rows: names ended in "…", counters in "1"
    /// (seen on macOS 14; the card's own layout was to blame, the drawing next to
    /// the text). There the card is the first, non-selectable row of the list.
    private static let cardInList: Bool = {
        if #available(macOS 26, *) { return false } else { return true }
    }()

    private var navigation: some View {
        List(selection: Binding(get: { window.sidebarSelection }, set: { if let item = $0 { window.select(item) } })) {
            if Self.cardInList {
                DeviceCard(inList: true)
                    .listRowInsets(EdgeInsets())
                    .selectionDisabled()
            }
            Section("Library") {
                ModuleLibraryItems()
            }
            ModuleSidebarSections()
        }
        .listStyle(.sidebar)
        // Feedback on top, not in Overview: a tester should have it at hand
        // the moment something goes wrong.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The same system list rows as Albums and Songs: the same typeface,
            // color and icon indent.
            List {
                Button { window.showFeedback() } label: { Label("Send Feedback", systemImage: "bubble.left") }
                Button { window.showAbout() } label: { Label("About \(AboutFacts.appName)", systemImage: "info.circle") }
            }
            .listStyle(.sidebar)
            .buttonStyle(.plain)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)
            .frame(height: 76)
        }
    }

}
