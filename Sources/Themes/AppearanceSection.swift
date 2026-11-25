import SwiftUI
import UniformTypeIdentifiers
import ClickwillShared

/// The Appearance section at the top of Settings: the built-in looks, and the user's own
/// themes with everything done to them. The save and open panels and the delete question
/// stay here, on the Settings window, not on the editor sheet.
public struct AppearanceSection: View {
    @Bindable private var store: ThemeStore

    @State private var editing: EditorDraft?
    @State private var exporting: CustomTheme?
    @State private var importing = false
    @State private var deleting: CustomTheme?
    @State private var notice: Notice?

    public init(store: ThemeStore) {
        self.store = store
    }

    public var body: some View {
        Section {
            Picker("Appearance", selection: builtInChoice) {
                ForEach(ThemeChoice.builtIn, id: \.self) { choice in
                    Text(choice.title ?? "").tag(Optional(choice))
                }
            }
            .pickerStyle(.segmented)
            if let library = store.library {
                ForEach(library.themes) { theme in
                    row(theme, in: library)
                }
                HStack {
                    Spacer()
                    Button("Import…") { importing = true }
                    Button("New Theme…") { editing = EditorDraft(theme: newTheme(), isNew: true) }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.clickwillTheme, .json]) { result in
                    guard case .success(let url) = result else { return }
                    importTheme(url, into: library)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text(store.library == nil
                 ? "With System, Clickwill turns light or dark together with your Mac."
                 : "With System, Clickwill turns light or dark together with your Mac. Control-click a theme of your own to edit, export or delete it.")
        }
        .sheet(item: $editing) { draft in
            ThemeEditor(theme: draft.theme, isNew: draft.isNew) { (theme: CustomTheme) throws(ThemeFileError) in
                try store.save(theme, choose: draft.isNew)
            }
        }
        .fileExporter(isPresented: exportShown, document: exporting.map(ThemeDocument.init),
                      contentType: .clickwillTheme, defaultFilename: exporting.map { ThemeName.fileName($0.name) }) { result in
            if case .failure(let error) = result, !Self.isCancellation(error) {
                notice = Notice(title: "I couldn't export the theme.", message: "")
            }
            exporting = nil
        }
        .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "", isPresented: deleteShown, presenting: deleting) { theme in
            Button("Delete", role: .destructive) { delete(theme) }
        } message: { _ in
            Text("The theme is removed from this Mac. A copy you exported stays where you saved it.")
        }
        .alert(notice?.title ?? "", isPresented: noticeShown, presenting: notice) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.message)
        }
    }

    /// The segmented control shows nothing selected while a custom theme is chosen, and
    /// picking a segment is the only thing that writes through it.
    private var builtInChoice: Binding<ThemeChoice?> {
        Binding(get: { ThemeChoice.builtIn.contains(store.choice) ? store.choice : nil },
                set: { if let choice = $0 { store.choice = choice } })
    }

    /// A new theme starts from the look on screen now.
    private func newTheme() -> CustomTheme {
        CustomTheme(name: "My Theme", start: store.current.palette.colorScheme == .light ? .light : .dark)
    }

    private func importTheme(_ url: URL, into library: ThemeLibrary) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let contents = try library.importTheme(from: url)
            if !contents.unknownColors.isEmpty {
                notice = Notice(title: "I added “\(contents.theme.name)”.", message: Self.skipped(contents.unknownColors))
            }
        } catch {
            notice = Notice(title: "I couldn't add this theme.", message: error.errorDescription ?? "")
        }
    }

    /// Closing the save panel without saving is not a failure.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }

    /// A short note on keys from a newer Clickwill: how many, and at most three names.
    static func skipped(_ keys: [String]) -> String {
        let names = keys.prefix(3).map { ThemeName.clean(String($0.prefix(30))) }.joined(separator: ", ")
        let more = keys.count > 3 ? " and \(keys.count - 3) more" : ""
        let count = keys.count == 1 ? "1 color" : "\(keys.count) colors"
        return "It has \(count) this version of Clickwill doesn't know (\(names)\(more)). I left them out."
    }

    private func row(_ theme: CustomTheme, in library: ThemeLibrary) -> some View {
        ThemeRow(theme: theme, chosen: store.choice == .custom(theme.id)) {
            store.choice = .custom(theme.id)
        }
        .contextMenu {
            Button("Edit…") { editing = EditorDraft(theme: theme, isNew: false) }
            Button("Duplicate") { duplicate(theme, in: library) }
            Button("Export…") { exporting = theme }
            Divider()
            Button("Delete…", role: .destructive) { deleting = theme }
        }
    }

    private func duplicate(_ theme: CustomTheme, in library: ThemeLibrary) {
        do { try library.duplicate(theme.id) } catch { show(error) }
    }

    private func delete(_ theme: CustomTheme) {
        do { try store.delete(theme.id) } catch { show(error) }
    }

    private func show(_ error: ThemeFileError) {
        notice = Notice(title: error.errorDescription ?? "", message: "")
    }

    private var exportShown: Binding<Bool> {
        Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } })
    }

    private var deleteShown: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    }

    private struct EditorDraft: Identifiable {
        let theme: CustomTheme
        let isNew: Bool
        var id: UUID { theme.id }
    }

    private struct Notice {
        let title: String
        let message: String
    }
}

/// One of the user's themes in Settings: its three colors, its name, and a check when chosen.
private struct ThemeRow: View {
    let theme: CustomTheme
    let chosen: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                HStack(spacing: -4) {
                    ForEach(ThemeToken.all) { token in
                        Circle().fill(theme.color(token)).overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                            .frame(width: 14, height: 14)
                    }
                }
                Text(theme.name)
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
