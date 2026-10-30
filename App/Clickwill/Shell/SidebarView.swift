import SwiftUI
import ClickwillModel

/// The sidebar: the iPod card, the library, discs in the drive, the device,
/// and at the bottom feedback and About.
struct SidebarView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(AudioCDStore.self) private var cds
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
                // Only an iPod that itself has Cover Flow - otherwise the tab would show
                // something the device does not have.
                if model.hasCoverFlow {
                    Label("Cover Flow", systemImage: "square.stack.3d.forward.dottedline")
                        .tag(SidebarItem.coverFlow)
                        .disabled(!loaded)
                }
                Label("Albums", systemImage: "square.stack")
                    .badge(loaded ? model.albumsDisplay.count : 0)
                    .tag(SidebarItem.albums)
                    .disabled(!loaded)
                Label("Artists", systemImage: "person.2")
                    .badge(loaded ? model.artistCount : 0)
                    .tag(SidebarItem.artists)
                    .disabled(!loaded)
                Label("Songs", systemImage: "music.note")
                    .badge(loaded ? model.trackCount : 0)
                    .tag(SidebarItem.songs)
                    .disabled(!loaded)
                // The file panel is opened here, not in the sheet: a modal window
                // started from inside a presented sheet does not show at all.
                Button {
                    window.showImport(ImportSheet.chooseFiles())
                } label: {
                    Label("Add Songs or Albums", systemImage: "plus")
                        .badge(model.changes.additions.count)
                }
                .buttonStyle(.plain)
                .disabled(!model.isWritable)
                .help(model.isWritable ? "" : model.writeUnavailable.map(ErrorPresenter.message(for:)) ?? "Connect an iPod to add songs.")
            }
            if !cds.discs.isEmpty {
                Section("Audio CD") {
                    ForEach(cds.discs) { disc in
                        Label(cds.session(disc.volume)?.title ?? disc.volumeName, systemImage: "opticaldisc")
                            .tag(SidebarItem.disc(disc.volume))
                            .contextMenu {
                                Button("Eject Disc") { cds.session(disc.volume)?.eject() }
                            }
                    }
                }
            }
            Section("Device") {
                Label("Overview", systemImage: "info.circle")
                    .tag(SidebarItem.overview)
                    .disabled(!loaded)
                // Backups were made on every write, and there was no way to use them
                // outside the command line.
                Label("Backups", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarItem.backups)
                    .disabled(!loaded || model.device == nil)
                    .help(model.device == nil ? "Backups belong to a connected iPod." : "")
            }
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

    /// Without a loaded library the panel has nothing to show and nowhere to lead.
    private var loaded: Bool { model.state == .loaded }
}
