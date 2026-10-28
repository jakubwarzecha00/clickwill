import Foundation

/// Moves the remembered position and size of the main window from the key used in releases
/// in which the window had no fixed identifier.
///
/// macOS saves the window frame (`NSWindow Frame …`) and the sidebar split
/// (`NSSplitView Subview Frames …`) under the window name. Without a scene identifier
/// the name came from the type of the whole main view; with an identifier it is fixed.
/// Without the move, the first launch of a new version would open the window
/// in the default place and size instead of where the user left it.
///
/// It runs before the window is created and only when there is nothing yet under the new
/// name - it never overwrites a new frame once remembered. The old keys
/// stay, so going back to an older version also opens the window in its place.
enum WindowFrameMigration {

    /// The window name under the fixed scene identifier (`WindowGroup(id:)`).
    static func windowName(sceneID: String) -> String { "\(sceneID)-AppWindow-1" }

    /// The main window name in all releases without a scene identifier -
    /// the view type was the same in all of them.
    static let legacyWindowName = "SwiftUI.WindowGroup<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<"
        + "SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Clickwill.ContentView, "
        + "SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<ClickwillModel.LibraryModel>>>, "
        + "SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<Clickwill.PlaybackController>>>, "
        + "SwiftUI._FlexFrameLayout>, SwiftUI._PreferenceWritingModifier<SwiftUI.PreferredColorSchemeKey>>, "
        + "SwiftUI._TaskModifier2>>-1-AppWindow-1"

    /// The keys under which AppKit keeps the window state; the window name is inside.
    private static let keyPrefixes = ["NSWindow Frame ", "NSSplitView Subview Frames "]

    static func run(sceneID: String, in defaults: UserDefaults = .standard) {
        let newName = windowName(sceneID: sceneID)
        guard defaults.object(forKey: keyPrefixes[0] + newName) == nil else { return }
        for (key, value) in defaults.dictionaryRepresentation() {
            guard keyPrefixes.contains(where: { key.hasPrefix($0 + legacyWindowName) }) else { continue }
            let newKey = key.replacingOccurrences(of: legacyWindowName, with: newName)
            if defaults.object(forKey: newKey) == nil { defaults.set(value, forKey: newKey) }
        }
    }
}
