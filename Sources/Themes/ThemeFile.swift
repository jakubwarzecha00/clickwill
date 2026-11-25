import Foundation

/// A `.clickwilltheme` file: JSON with a format number, a name, a base and colors.
///
/// The file is untrusted. It is read up to a size limit before any parsing, the format must
/// be exactly 1, and a bad base or a bad color rejects the whole file. Keys this version does
/// not know are skipped and counted, so a theme from a newer Clickwill still opens.
public enum ThemeFile {
    public static let fileExtension = "clickwilltheme"
    public static let maxBytes = 64 * 1024
    static let format = 1

    public struct Contents: Sendable, Equatable {
        public let theme: CustomTheme
        /// Color keys the file had that this version does not know; skipped.
        public let unknownColors: [String]
    }

    /// Reads at most `maxBytes + 1` bytes, so a large file is never pulled in whole.
    public static func read(from url: URL, id: UUID) throws(ThemeFileError) -> Contents {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        } catch {
            throw .unreadable
        }
        return try read(data, id: id)
    }

    public static func read(_ data: Data, id: UUID) throws(ThemeFileError) -> Contents {
        guard data.count <= maxBytes else { throw .tooLarge }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw .notATheme }

        guard let number = root["format"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw .notATheme
        }
        guard number.doubleValue == Double(format) else {
            throw number.doubleValue > Double(format) ? .newerFormat : .notATheme
        }
        guard let baseName = root["base"] as? String, let base = CustomTheme.Base(rawValue: baseName) else {
            throw .badBase
        }
        let name = ThemeName.clean(root["name"] as? String ?? "")

        var colors: [String: String] = [:]
        var unknown: [String] = []
        if let value = root["colors"] {
            guard let entries = value as? [String: Any] else { throw .notATheme }
            for (key, value) in entries {
                guard ThemeToken.named(key) != nil else { unknown.append(key); continue }
                guard let text = value as? String, let hex = HexColor.normalized(text) else { throw .badColor(key) }
                colors[key] = hex
            }
        }
        return Contents(theme: CustomTheme(id: id, name: name, base: base, colors: colors),
                        unknownColors: unknown.sorted())
    }

    /// The file's JSON with only the keys this version knows.
    public static func data(_ theme: CustomTheme) -> Data {
        let root: [String: Any] = [
            "format": format,
            "name": ThemeName.clean(theme.name),
            "base": theme.base.rawValue,
            "colors": theme.colors,
        ]
        // Only strings and an integer: serialization cannot fail.
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

/// Why a theme could not be opened or kept. The text names no path.
public enum ThemeFileError: Error, Equatable, LocalizedError {
    case unreadable
    case tooLarge
    case notATheme
    case newerFormat
    case badBase
    case badColor(String)
    case cannotSave

    public var errorDescription: String? {
        switch self {
        case .unreadable: "I couldn't read this file."
        case .tooLarge: "This file is too large to be a Clickwill theme."
        case .notATheme: "This file isn't a Clickwill theme."
        case .newerFormat: "This theme was made for a newer Clickwill. Update Clickwill to use it."
        case .badBase: "This theme doesn't say whether it is light or dark."
        case .badColor(let key): "The color “\(key)” in this theme isn't a hex color like #2F6AA8."
        case .cannotSave: "I couldn't save the theme on this Mac."
        }
    }
}
