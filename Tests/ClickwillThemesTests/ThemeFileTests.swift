import Foundation
import SwiftUI
import Testing
import ClickwillShared
@testable import ClickwillThemes

struct ThemeFileTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }
    private let id = UUID()

    @Test func readsAThemeAndStartsMissingColorsFromDark() throws {
        let contents = try ThemeFile.read(json(##"{"format":1,"name":"Sunset","colors":{"accent":"#e07a5f"}}"##), id: id)
        #expect(contents.theme.name == "Sunset")
        #expect(contents.theme.colors == ["accent": "#E07A5F", "background": "#1C1C1E", "scene": "#0B0B0D"])
        #expect(contents.unknownColors.isEmpty)
        #expect(try ThemeFile.read(json(##"{"format":1}"##), id: id).theme.name == "Untitled Theme")
    }

    @Test func unknownKeysAreSkippedAndCounted() throws {
        let contents = try ThemeFile.read(json(##"{"format":1,"base":"dark","extra":true,"colors":{"bg":"#FFFFFF","glow":"not a color"}}"##), id: id)
        #expect(contents.unknownColors == ["bg", "glow"])
        #expect(contents.theme.colors == CustomTheme(name: "", start: .dark).colors)
    }

    @Test func aTransparentColorIsKeptOpaque() throws {
        let contents = try ThemeFile.read(json(##"{"format":1,"colors":{"scene":"#C80AF580"}}"##), id: id)
        #expect(contents.theme.colors["scene"] == "#C80AF5")
    }

    @Test func theFormatMustBeExactlyOne() {
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"name":"x"}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":0}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":true}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":"1"}"##), id: id) }
        #expect(throws: ThemeFileError.newerFormat) { try ThemeFile.read(json(##"{"format":2}"##), id: id) }
    }

    @Test func aBadColorRejectsTheFile() {
        for bad in ["#FFF", "FFFFFF", "#GGGGGG", "#FFFFFFF", "#FFFFFFFFF", "red", "#ＦＦＦＦＦＦ"] {
            #expect(throws: ThemeFileError.badColor("accent")) {
                try ThemeFile.read(json(##"{"format":1,"colors":{"accent":"\##(bad)"}}"##), id: id)
            }
        }
        #expect(throws: ThemeFileError.badColor("background")) { try ThemeFile.read(json(##"{"format":1,"colors":{"background":12}}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json(##"{"format":1,"colors":[]}"##), id: id) }
        #expect(throws: ThemeFileError.notATheme) { try ThemeFile.read(json("[1]"), id: id) }
    }

    @Test func aLargeFileIsNotReadWhole() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("big.clickwilltheme")
        let padding = String(repeating: " ", count: ThemeFile.maxBytes)
        try Data((##"{"format":1}"## + padding).utf8).write(to: file)
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
        var theme = CustomTheme(name: "Every Color", start: .light)
        for (index, token) in ThemeToken.all.enumerated() {
            let value = Double(index + 1) / Double(ThemeToken.all.count + 1)
            theme.set(Color(.sRGB, red: value, green: 1 - value, blue: 0.5), for: token)
        }
        let back = try ThemeFile.read(ThemeFile.data(theme), id: theme.id).theme
        #expect(back == theme)
        for token in ThemeToken.all {
            #expect(HexColor.string(back.color(token)) == theme.colors[token.key])
        }
    }

    @Test func theSavedFileHoldsOnlyKnownKeys() throws {
        let theme = CustomTheme(name: "Sunset", colors: ["accent": "#e07a5f", "glow": "#FFFFFF", "scene": "bad"])
        let root = try #require(try JSONSerialization.jsonObject(with: ThemeFile.data(theme)) as? [String: Any])
        #expect(Set(root.keys) == ["format", "name", "colors"])
        #expect(root["colors"] as? [String: String] == ["accent": "#E07A5F", "background": "#1C1C1E", "scene": "#0B0B0D"])
    }
}

struct ThemeTokenTests {
    @Test func aThemeIsThreeColors() {
        #expect(ThemeToken.all.map(\.key) == ["accent", "background", "scene"])
        #expect(ThemeToken.all.allSatisfy { !$0.detail.contains("–") })
    }

    @Test func aPickedColorDropsItsAlpha() {
        var theme = CustomTheme(name: "T")
        theme.set(Color.red.opacity(0.5), for: .accent)
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
