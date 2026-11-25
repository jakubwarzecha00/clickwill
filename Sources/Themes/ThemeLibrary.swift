import Foundation
import Observation

/// The user's themes: one file per theme in a folder the app gives (Application Support,
/// or a temporary folder in demo mode). File names are identities this class makes, never
/// a theme's name or anything from a file's content.
@MainActor
@Observable
public final class ThemeLibrary {
    /// Sorted by name.
    public private(set) var themes: [CustomTheme] = []
    @ObservationIgnored private let folder: URL

    public init(folder: URL) {
        self.folder = folder
        reload()
    }

    public func theme(_ id: UUID) -> CustomTheme? {
        themes.first { $0.id == id }
    }

    /// Reads the folder again. A file that does not open is left out, never stops the list.
    public func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        themes = files.compactMap { file -> CustomTheme? in
            guard file.pathExtension == ThemeFile.fileExtension,
                  let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { return nil }
            return try? ThemeFile.read(from: file, id: id).theme
        }
        .sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }

    public func save(_ theme: CustomTheme) throws(ThemeFileError) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ThemeFile.data(theme).write(to: file(theme.id), options: .atomic)
        } catch {
            throw .cannotSave
        }
        reload()
    }

    public func delete(_ id: UUID) throws(ThemeFileError) {
        do { try FileManager.default.removeItem(at: file(id)) } catch { throw .cannotSave }
        reload()
    }

    @discardableResult
    public func duplicate(_ id: UUID) throws(ThemeFileError) -> CustomTheme? {
        guard let copy = theme(id)?.duplicate() else { return nil }
        try save(copy)
        return copy
    }

    /// Checks a file from anywhere and keeps a clean copy under a new identity.
    public func importTheme(from url: URL) throws(ThemeFileError) -> ThemeFile.Contents {
        let contents = try ThemeFile.read(from: url, id: UUID())
        try save(contents.theme)
        return contents
    }

    private func file(_ id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString, isDirectory: false)
            .appendingPathExtension(ThemeFile.fileExtension)
    }
}
