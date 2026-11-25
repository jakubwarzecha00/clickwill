import Foundation
import Testing
import ClickwillShared
@testable import ClickwillThemes

@MainActor
struct ThemeLibraryTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString)")

    @Test func savesListsAndDeletes() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ThemeLibrary(folder: folder)
        #expect(library.themes.isEmpty)
        let b = CustomTheme(name: "b"), a = CustomTheme(name: "A", start: .light)
        try library.save(b)
        try library.save(a)
        #expect(library.themes.map(\.name) == ["A", "b"])
        #expect(ThemeLibrary(folder: folder).themes == library.themes)
        try library.delete(a.id)
        #expect(library.themes == [b])
    }

    @Test func aBrokenFileIsLeftOutOfTheList() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ThemeLibrary(folder: folder)
        try library.save(CustomTheme(name: "Good"))
        try Data("{".utf8).write(to: folder.appendingPathComponent(UUID().uuidString + ".clickwilltheme"))
        try Data(##"{"format":1}"##.utf8).write(to: folder.appendingPathComponent("not-an-id.clickwilltheme"))
        library.reload()
        #expect(library.themes.map(\.name) == ["Good"])
    }

    @Test func aDuplicateIsACopyWithItsOwnFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ThemeLibrary(folder: folder)
        let long = CustomTheme(name: String(repeating: "x", count: 60), colors: ["accent": "#E07A5F"])
        try library.save(long)
        let copy = try #require(try library.duplicate(long.id))
        #expect(copy.id != long.id)
        #expect(copy.name == String(repeating: "x", count: 55) + " Copy")
        #expect(copy.colors == long.colors)
        #expect(library.themes.count == 2)
        #expect(CustomTheme(name: "Sunset").duplicate().name == "Sunset Copy")
    }

    @Test func anImportIsKeptCleanUnderANewIdentity() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("../\(UUID().uuidString).clickwilltheme")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(##"{"format":1,"name":"Sunset","colors":{"accent":"#E07A5F","glow":"#FFF"},"extra":1}"##.utf8).write(to: outside)
        let library = ThemeLibrary(folder: folder)
        let contents = try library.importTheme(from: outside)
        #expect(contents.unknownColors == ["glow"])
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files == [contents.theme.id.uuidString + ".clickwilltheme"])
        let kept = try String(contentsOf: folder.appendingPathComponent(files[0]), encoding: .utf8)
        #expect(!kept.contains("glow") && !kept.contains("extra"))
    }

    @Test func aBadImportAddsNothingAndNamesNoPath() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).clickwilltheme")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(##"{"format":1,"colors":{"accent":"#XYZXYZ"}}"##.utf8).write(to: outside)
        let library = ThemeLibrary(folder: folder)
        do {
            _ = try library.importTheme(from: outside)
            Issue.record("imported a bad file")
        } catch {
            #expect(!(error.errorDescription ?? "").contains("/"))
        }
        #expect(library.themes.isEmpty)
    }
}

@MainActor
struct CustomThemeChoiceTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("themes-\(UUID().uuidString)")

    @Test func choicesAreParsedByHand() {
        let id = UUID()
        for choice in [ThemeChoice.system, .light, .dark, .custom(id)] {
            #expect(ThemeChoice(storageValue: choice.storageValue) == choice)
        }
        #expect(ThemeChoice(storageValue: "custom:nope") == nil)
        #expect(ThemeChoice(storageValue: "Light") == nil)
    }

    @Test func aChosenCustomThemeIsShownAndSurvivesALaunch() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = ThemeLibrary(folder: folder)
        let storage = ThemeStore.Storage.memory()
        let store = ThemeStore(storage: storage, system: SystemAppearance(isDark: true), library: library)
        let theme = CustomTheme(name: "Sunset", start: .light, colors: ["accent": "#E07A5F"])
        try store.save(theme, choose: true)
        #expect(store.current.palette == theme.palette)
        #expect(storage.load() == "custom:" + theme.id.uuidString)
        let again = ThemeStore(storage: storage, system: SystemAppearance(isDark: true), library: ThemeLibrary(folder: folder))
        #expect(again.choice == .custom(theme.id))
        #expect(again.current.palette == theme.palette)
    }

    @Test func savingAnotherThemeDoesNotChooseIt() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ThemeStore(storage: .memory(), system: SystemAppearance(isDark: true), library: ThemeLibrary(folder: folder))
        try store.save(CustomTheme(name: "Kept", start: .light), choose: false)
        #expect(store.choice == .system)
    }

    @Test func aMissingChosenThemeShowsSystemAndKeepsTheChoice() {
        let id = UUID()
        let storage = ThemeStore.Storage.memory("custom:" + id.uuidString)
        let store = ThemeStore(storage: storage, system: SystemAppearance(isDark: false), library: ThemeLibrary(folder: folder))
        #expect(store.current.palette == .light)
        #expect(store.choice == .custom(id))
        #expect(storage.load() == "custom:" + id.uuidString)
    }

    @Test func deletingTheChosenThemeGoesBackToSystem() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = ThemeStore.Storage.memory()
        let store = ThemeStore(storage: storage, system: SystemAppearance(isDark: true), library: ThemeLibrary(folder: folder))
        let chosen = CustomTheme(name: "Chosen"), other = CustomTheme(name: "Other")
        try store.save(other, choose: false)
        try store.save(chosen, choose: true)
        try store.delete(other.id)
        #expect(store.choice == .custom(chosen.id))
        try store.delete(chosen.id)
        #expect(store.choice == .system)
        #expect(storage.load() == "system")
    }

    @Test func closingTheSavePanelIsNotAnError() {
        #expect(AppearanceSection.isCancellation(CancellationError()))
        #expect(AppearanceSection.isCancellation(CocoaError(.userCancelled)))
        #expect(!AppearanceSection.isCancellation(CocoaError(.fileWriteNoPermission)))
    }

    @Test func theNoteOnSkippedColorsIsShort() {
        #expect(AppearanceSection.skipped(["glow"]) == "It has 1 color this version of Clickwill doesn't know (glow). I left them out.")
        #expect(AppearanceSection.skipped(["a", "b", "c", "d", "e"]).contains("(a, b, c and 2 more)"))
    }
}
