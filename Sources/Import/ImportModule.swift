import SwiftUI
import ClickwillModel
import ClickwillShared

/// The Library row that opens Add Songs. The file panel opens here, before the sheet:
/// a modal panel started from inside a presented sheet does not show at all.
public struct ImportSidebarItem: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.importActions) private var actions

    public init() {}

    public var body: some View {
        Button {
            actions.addFiles(ImportSheet.chooseFiles())
        } label: {
            Label("Add Songs or Albums", systemImage: "plus")
                .badge(model.changes.additions.count)
        }
        .buttonStyle(.plain)
        .disabled(!model.isWritable)
        .help(model.isWritable ? "" : model.writeUnavailable.map(ErrorPresenter.message(for:)) ?? "Connect an iPod to add songs.")
    }
}

/// What Add Songs asks the window to do.
public struct ImportActions: Sendable {
    /// Opens the Add Songs sheet with these files; an empty list (a cancelled panel) does nothing.
    public var addFiles: @MainActor @Sendable ([URL]) -> Void

    public init(addFiles: @escaping @MainActor @Sendable ([URL]) -> Void) {
        self.addFiles = addFiles
    }

    static let none = ImportActions(addFiles: { _ in })
}

public extension EnvironmentValues {
    @Entry var importActions: ImportActions = .none
}
