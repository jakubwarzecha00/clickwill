import Foundation
import SwiftUI
import Testing
import ClickwillShared
@testable import ClickwillThemes

struct ThemeFileTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }
    private let id = UUID()

    @Test func readsAThemeAndTakesMissingColorsFromTheBase() throws {
        let contents = try ThemeFile.read(json(##"{"format":1,"name":"Sunset","base":"dark","colors":{"accent":"#e07a5f"}}"##), id: id)
        #expect(contents.theme.name == "Sunset")
        #expect(contents.theme.base == .dark)
        #expect(contents.theme.colors == ["accent": "#E07A5F"])
        #expect(contents.theme.palette.bg == ThemePalette.dark.bg)
        #expect(contents.unknownColors.isEmpty)
    }

    @Test func emptyOrMissingColorsAreTheBase() throws {
        #expect(try ThemeFile.read(json(##"{"format":1,"base":"light","colors":{}}"##), id: id).theme.palette == .light)
        #expect(try ThemeFile.read(json(##"{"format":1,"base":"light"}"##), id: id).theme.name == "Untitled Theme")
    }

    @Test func unknownKeysAreSkippedAndCounted() throws {
        let contents = try ThemeFile.read(json(##"{"format":1,"base":"dark","extra":true,"colors":{"glow":"#FFFFFF","halo":"not a color"}}"##), id: id)
        #expect(contents.unknownColors == ["glow", "halo"])
        #expect(contents.theme.colors.isEmpty)
    }

    @Test func theFormatMustBeExactlyOne() {
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"base":"dark"}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":0,"base":"dark"}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":true,"base":"dark"}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":"1","base":"dark"}"##), id: id) }
        #expect(throws: ThemeFileError.newerFormat) { try ThemeFile.read(json(##"{"format":2,"base":"dark"}"##), id: id) }
    }

    @Test func aBadBaseOrColorRejectsTheFile() {
        #expect(throws: ThemeFileError.badBase) { try ThemeFile.read(json(##"{"format":1,"base":"sepia"}"##), id: id) }
        #expect(throws: ThemeFileError.badBase) { try ThemeFile.read(json(##"{"format":1}"##), id: id) }
        for bad in ["#FFF", "FFFFFF", "#GGGGGG", "#FFFFFFF", "#FFFFFFFFF", "red", "#ＦＦＦＦＦＦ"] {
            #expect(throws: ThemeFileError.badColor("accent")) {
                try ThemeFile.read(json(##"{"format":1,"base":"dark","colors":{"accent":"\##(bad)"}}"##), id: id)
            }
        }
        #expect(throws: ThemeFileError.badColor("bg")) { try ThemeFile.read(json(##"{"format":1,"base":"dark","colors":{"bg":12}}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":1,"base":"dark","colors":[]}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json("[1]"), id: id) }
    }

    @Test func aLargeFileIsNotReadWhole() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("big.clickwilltheme")
        let padding = String(repeating: " ", count: ThemeFile.maxBytes)
        try Data((##"{"format":1,"base":"dark"}"## + padding).utf8).write(to: file)
        #expect(throws: ThemeFileError.tooLarge) { try ThemeFile.read(from: file, id: id) }
        #expect(throws: ThemeFileError.unreadable) { try ThemeFile.read(from: folder.appendingPathComponent("none"), id: id) }
    }

    @Test func aNameLosesControlAndDirectionCharactersAndIsCut() {
        #expect(ThemeName.clean("Sun\u{202E}set\u{0007}\n") == "Sunset")
        #expect(ThemeName.clean("\u{2066}  \u{2069}") == "Untitled Theme")
        #expect(ThemeName.clean(String(repeating: "a", count: 80)).count == 60)
        #expect(ThemeName.fileName("Night/Day: 2") == "Night-Day- 2")
    }

    @Test func everyColorSurvivesExportAndImport() throws {
        var theme = CustomTheme(name: "Every Color", base: .light)
        for (index, token) in ThemeToken.all.enumerated() {
            let value = Double(index) / Double(ThemeToken.all.count)
            theme.set(Color(.sRGB, red: value, green: 1 - value, blue: 0.5, opacity: token.allowsOpacity ? 0.5 : 1), for: token)
        }
        let back = try ThemeFile.read(ThemeFile.data(theme), id: theme.id).theme
        #expect(back == theme)
        for token in ThemeToken.all {
            #expect(HexColor.string(back.color(token)) == theme.colors[token.key])
        }
    }

    @Test func theSavedFileHoldsOnlyKnownKeys() throws {
        let theme = CustomTheme(name: "Sunset", base: .dark, colors: ["accent": "#e07a5f", "glow": "#FFFFFF", "bg": "bad"])
        let root = try #require(try JSONSerialization.jsonObject(with: ThemeFile.data(theme)) as? [String: Any])
        #expect(Set(root.keys) == ["format", "name", "base", "colors"])
        #expect(root["colors"] as? [String: String] == ["accent": "#E07A5F"])
    }
}

struct ThemeTokenTests {
    /// Every color of a palette is in the editor once; the light or dark scheme is not a color.
    @Test func everyPaletteColorIsInExactlyOneGroup() {
        let fields = Mirror(reflecting: ThemePalette.dark).children.compactMap(\.label).filter { $0 != "colorScheme" }
        let keys = ThemeToken.groups.flatMap { $0.tokens.map(\.key) }
        #expect(keys.count == Set(keys).count)
        #expect(Set(keys) == Set(fields))
        for token in ThemeToken.all {
            #expect(Mirror(reflecting: ThemePalette.dark).children.first { $0.label == token.key }?.value is Color)
        }
    }

    @Test func opacityIsOfferedForTheTransparentColorsOfTheDesign() {
        let withOpacity = Set(ThemeToken.all.filter(\.allowsOpacity).map(\.key))
        #expect(withOpacity == ["f2", "f3", "sep", "sel", "glassBorder", "row", "rowHover", "trackHover",
                                "field", "fieldBorder", "sceneShadow"])
    }

    @Test func anOpaqueColorDropsItsAlpha() {
        var theme = CustomTheme(name: "T", base: .dark)
        theme.set(Color.red.opacity(0.5), for: ThemeToken.named("accent")!)
        #expect(theme.colors["accent"]?.count == 7)
    }
}

struct ThemeContrastTests {
    @Test func theBuiltInThemesReadClearly() {
        #expect(ThemeContrast.warnings(.light).isEmpty)
        #expect(ThemeContrast.warnings(.dark).isEmpty)
    }

    @Test func theDarkAccentBadgeIsTheDesign() {
        let ratio = ThemeContrast.ratio(ThemePalette.dark.onAccent, on: ThemePalette.dark.accent)
        #expect(ratio > ThemeContrast.onAccentMinimum && ratio < 3)
    }

    @Test func aPaletteThatDoesNotReadGetsAWarningForEachPlace() {
        var palette = ThemePalette.dark
        palette.fg = Color(white: 0.2)
        palette.f2 = Color(white: 0.15)
        palette.accent = Color(white: 0.14)
        palette.onAccent = Color(white: 0.15)
        palette.sceneText = Color(white: 0.06)
        palette.sliderKnob = Color(white: 0.1)
        let warnings = ThemeContrast.warnings(palette)
        #expect(warnings.count == 6)
        #expect(warnings.allSatisfy { !$0.message.contains("–") && $0.message.contains(":1") })
    }
}
