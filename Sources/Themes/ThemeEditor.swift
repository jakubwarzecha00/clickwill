import SwiftUI
import ClickwillShared

/// What the themes module asks the window to do: show the editor page, and leave it.
public struct ThemeActions: Sendable {
    public var showEditor: @MainActor @Sendable (_ isNew: Bool) -> Void
    public var closeEditor: @MainActor @Sendable () -> Void

    public init(showEditor: @escaping @MainActor @Sendable (Bool) -> Void,
                closeEditor: @escaping @MainActor @Sendable () -> Void) {
        self.showEditor = showEditor
        self.closeEditor = closeEditor
    }
}

public extension EnvironmentValues {
    @Entry var themeActions = ThemeActions(showEditor: { _ in }, closeEditor: {})
}

/// The page of the library window for making or changing one of the user's themes: the
/// theme `ThemeStore.editing` names. Nothing outside the page changes until Add Theme or Save.
public struct ThemeEditorPage: View {
    @Bindable private var store: ThemeStore
    @Environment(\.themeActions) private var actions

    public init(store: ThemeStore) {
        self.store = store
    }

    public var body: some View {
        if let editing = store.editing {
            ThemeEditor(theme: editing.theme, isNew: editing.isNew) { (theme: CustomTheme) throws(ThemeFileError) in
                try store.save(theme, choose: editing.isNew)
            } close: {
                store.editing = nil
                actions.closeEditor()
            }
            .id(editing.id)
        }
    }
}

/// The name and the three colors on the left, the window in those colors on the right.
struct ThemeEditor: View {
    @State private var draft: CustomTheme
    @State private var failure: String?
    let isNew: Bool
    let save: (CustomTheme) throws(ThemeFileError) -> Void
    let close: () -> Void

    init(theme: CustomTheme, isNew: Bool, save: @escaping (CustomTheme) throws(ThemeFileError) -> Void,
         close: @escaping () -> Void) {
        _draft = State(initialValue: theme)
        self.isNew = isNew
        self.save = save
        self.close = close
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                form
                    .frame(width: 400)
                // Scrolls, so no warning can make the page taller than the window: a page
                // that cannot fit pushes the whole window past the screen's edges.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ThemeThumbnail(palette: draft.palette)
                            .frame(maxWidth: 640)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Preview of the theme")
                        warnings
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                    .padding(.trailing, 24)
                }
            }
            Divider()
            HStack {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { close() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Theme" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
            }
            Section {
                ForEach(ThemeToken.all) { token in
                    ColorPicker(selection: binding(token), supportsOpacity: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.title)
                            Text(token.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("I work out every other color from these three, so text stays readable and the Cover Flow floor matches its scene.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder private var warnings: some View {
        let warnings = ThemeContrast.warnings(draft.palette)
        if warnings.isEmpty {
            Label("Everything reads clearly.", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .symbolRenderingMode(.multicolor)
                }
                Text("You can still save it.").foregroundStyle(.secondary)
            }
        }
    }

    private func binding(_ token: ThemeToken) -> Binding<Color> {
        Binding(get: { draft.color(token) }, set: { draft.set($0, for: token) })
    }

    private func commit() {
        draft.name = ThemeName.clean(draft.name)
        do {
            try save(draft)
            close()
        } catch {
            failure = error.errorDescription
        }
    }
}
