import SwiftUI
import UniformTypeIdentifiers

public extension UTType {
    /// Declared by the app (`UTExportedTypeDeclarations` in its Info.plist), so the save
    /// panel keeps the extension.
    static let clickwillTheme = UTType(exportedAs: "pl.jakubwarzecha.clickwill.theme", conformingTo: .json)
}

/// A theme on its way out through the save panel.
struct ThemeDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.clickwillTheme]

    let data: Data

    init(_ theme: CustomTheme) {
        data = ThemeFile.data(theme)
    }

    /// Never used to open a theme: import goes through `ThemeLibrary.importTheme`, which
    /// checks the file.
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
