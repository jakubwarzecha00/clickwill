import SwiftUI
import UniformTypeIdentifiers
import ClickwillShared

/// The Appearance section at the top of Settings: a window in each look to pick from - the
/// built-in ones and the user's own - and everything done to the user's themes. The editor
/// is a page of the window (`ThemeEditorPage`); the save and open panels and the delete
/// question stay here.
public struct AppearanceSection: View {
    @Bindable private var store: ThemeStore
    @Environment(\.themeActions) private var actions

    @State private var exporting: CustomTheme?
    @State private var importing = false
    @State private var deleting: CustomTheme?
    @State private var notice: Notice?

    public init(store: ThemeStore) {
        self.store = store
    }

    private let columns = [GridItem(.adaptive(minimum: 116, maximum: 150), spacing: 16, alignment: .top)]

    public var body: some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(ThemeChoice.builtIn, id: \.self) { choice in
                    ThemeTile(title: choice.title ?? "", chosen: store.choice == choice) {
                        store.choice = choice
                    } picture: {
                        if choice == .system {
                            SystemThumbnail()
                        } else {
                            ThemeThumbnail(palette: choice.palette(systemIsDark: choice == .dark))
                        }
                    }
                }
                if let library = store.library {
                    ForEach(library.themes) { theme in
                        tile(theme, in: library)
                    }
                    NewThemeTile { edit(newTheme(), isNew: true) }
                }
            }
            .padding(.vertical, 4)
            if let library = store.library {
                HStack {
                    Spacer()
                    Button("Import…") { importing = true }
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

    /// Opens the editor page on this theme.
    private func edit(_ theme: CustomTheme, isNew: Bool) {
        store.editing = ThemeStore.ThemeEditing(theme: theme, isNew: isNew)
        actions.showEditor(isNew)
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

    private func tile(_ theme: CustomTheme, in library: ThemeLibrary) -> some View {
        ThemeTile(title: theme.name, chosen: store.choice == .custom(theme.id)) {
            store.choice = .custom(theme.id)
        } picture: {
            ThemeThumbnail(palette: theme.palette)
        }
        .contextMenu {
            Button("Edit…") { edit(theme, isNew: false) }
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

    private struct Notice {
        let title: String
        let message: String
    }
}

/// One look to pick in Settings: a window in its colors, its name under it, and a ring
/// around the window when chosen.
private struct ThemeTile<Picture: View>: View {
    let title: String
    let chosen: Bool
    let choose: () -> Void
    @ViewBuilder let picture: Picture

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                picture
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(chosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 3)
                    }
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(chosen ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The last tile: a new theme, starting from the look on screen.
private struct NewThemeTile: View {
    let action: () -> Void

    var body: some View {
        ThemeTile(title: "New Theme…", chosen: false, choose: action) {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .overlay { Image(systemName: "plus").font(.title2).foregroundStyle(.secondary) }
                .aspectRatio(ThemeThumbnail.aspectRatio, contentMode: .fit)
        }
    }
}
