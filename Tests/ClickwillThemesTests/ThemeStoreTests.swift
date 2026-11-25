import Testing
import ClickwillShared
@testable import ClickwillThemes

@MainActor
struct ThemeStoreTests {
    @Test func followsTheSystemWhenNothingWasChosen() {
        let system = SystemAppearance(isDark: true)
        let store = ThemeStore(storage: .memory(), system: system)
        #expect(store.choice == .system)
        #expect(store.current.palette == .dark)
    }

    @Test func aChangeOfTheMacsSettingChangesTheSystemTheme() {
        let system = SystemAppearance(isDark: false)
        let store = ThemeStore(storage: .memory(), system: system)
        #expect(store.current.palette == .light)
        system.setForTesting(isDark: true)
        #expect(store.current.palette == .dark)
    }

    @Test func aFixedChoiceIgnoresTheMac() {
        let system = SystemAppearance(isDark: true)
        let store = ThemeStore(storage: .memory(), system: system)
        store.choice = .light
        #expect(store.current.palette == .light)
        system.setForTesting(isDark: false)
        store.choice = .dark
        #expect(store.current.palette == .dark)
    }

    @Test func theChoiceIsKeptBetweenLaunches() {
        let storage = ThemeStore.Storage.memory()
        ThemeStore(storage: storage, system: SystemAppearance(isDark: true)).choice = .light
        #expect(ThemeStore(storage: storage, system: SystemAppearance(isDark: true)).choice == .light)
    }

    @Test func anUnknownSavedValueMeansSystemAndStaysUntouched() {
        let storage = ThemeStore.Storage.memory("sepia")
        let store = ThemeStore(storage: storage, system: SystemAppearance(isDark: false))
        #expect(store.choice == .system)
        #expect(storage.load() == "sepia")
    }

    @Test func aLaunchChoiceIsNotSaved() {
        let storage = ThemeStore.Storage.memory("dark")
        let store = ThemeStore(storage: storage, system: SystemAppearance(isDark: true), launchChoice: .light)
        #expect(store.current.palette == .light)
        #expect(storage.load() == "dark")
    }
}
