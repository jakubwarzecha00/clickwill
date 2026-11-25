import SwiftUI
import ClickwillShared

/// Making or changing one of the user's themes: its name, its base and its colors, with a
/// preview drawn from the draft. Nothing outside the sheet changes until Save.
struct ThemeEditor: View {
    @State private var draft: CustomTheme
    @State private var failure: String?
    let isNew: Bool
    let save: (CustomTheme) throws(ThemeFileError) -> Void
    @Environment(\.dismiss) private var dismiss

    init(theme: CustomTheme, isNew: Bool, save: @escaping (CustomTheme) throws(ThemeFileError) -> Void) {
        _draft = State(initialValue: theme)
        self.isNew = isNew
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                colors
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    ThemePreview(palette: draft.palette)
                    warnings
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(width: 300)
            }
            Divider()
            HStack {
                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Theme" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 780, height: 620)
    }

    private var colors: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Picker("Based on", selection: $draft.base) {
                    ForEach(CustomTheme.Base.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Colors you don't change come from the theme it is based on.")
            }
            ForEach(ThemeToken.groups) { group in
                Section(group.title) {
                    ForEach(group.tokens) { token in
                        HStack {
                            ColorPicker(token.title, selection: binding(token), supportsOpacity: token.allowsOpacity)
                            if draft.isChanged(token) {
                                Button("Reset") { draft.reset(token) }
                                    .buttonStyle(.borderless)
                                    .help("Back to the color of \(draft.base.title)")
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("You can still save it.").foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func binding(_ token: ThemeToken) -> Binding<Color> {
        Binding(get: { draft.color(token) }, set: { draft.set($0, for: token) })
    }

    private func commit() {
        draft.name = ThemeName.clean(draft.name)
        do {
            try save(draft)
            dismiss()
        } catch {
            failure = error.errorDescription
        }
    }
}
