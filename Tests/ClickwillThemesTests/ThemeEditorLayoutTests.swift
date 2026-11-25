import AppKit
import SwiftUI
import Testing
import ClickwillShared
@testable import ClickwillThemes

/// The editor is a page of the library window, so whatever it shows must fit any window
/// the user can make, or the whole window is pushed past the screen's edges.
@MainActor
struct ThemeEditorLayoutTests {
    private func smallestSize(_ theme: CustomTheme) -> CGSize {
        let editor = ThemeEditor(theme: theme, isNew: true, save: { _ in }, close: {})
        return NSHostingController(rootView: editor).sizeThatFits(in: .zero)
    }

    @Test func warningsDoNotMakeTheEditorTaller() {
        let clear = CustomTheme(name: "Clear", start: .dark)
        var faded = clear
        faded.set(Color(.sRGB, red: 0.12, green: 0.12, blue: 0.4), for: .accent)
        #expect(ThemeContrast.warnings(clear.palette).isEmpty)
        #expect(!ThemeContrast.warnings(faded.palette).isEmpty)

        let withoutWarnings = smallestSize(clear), withWarnings = smallestSize(faded)
        #expect(withWarnings.height <= withoutWarnings.height,
                "without \(withoutWarnings), with \(withWarnings)")
        #expect(withWarnings.height < 600, "with warnings \(withWarnings)")
    }
}
