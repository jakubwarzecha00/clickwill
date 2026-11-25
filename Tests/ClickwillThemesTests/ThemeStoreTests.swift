import CoreGraphics
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

    @Test func viceBringsItsSunsetAndNoOtherThemeHasOne() {
        let store = ThemeStore(storage: .memory(), system: SystemAppearance(isDark: true))
        #expect(store.current.sceneBackdrop == nil)
        store.choice = .vice
        #expect(store.current.palette == .vice)
        #expect(store.current.sceneBackdrop == .sunset)
        store.choice = .light
        #expect(store.current.sceneBackdrop == nil)
    }

    /// Text on Vice's cards and quieter text read as well as in the built-in dark theme.
    @Test func viceReadsOnItsCards() {
        let vice = ThemePalette.vice
        #expect(ThemeContrast.ratio(vice.fg, on: vice.card) >= 4.5)
        #expect(ThemeContrast.ratio(vice.f2, on: vice.card) >= 3.2)
        #expect(ThemeContrast.ratio(vice.sceneText, on: vice.floorTop) >= 3)
    }

    /// The sunset is one unbroken gradient whose coral glow sits on the horizon, wherever
    /// the horizon is, and which ends in the night of the bar under the slider.
    @Test func theSunsetGlowsOnTheHorizonAndEndsInNight() {
        for horizon in [0.6, 0.7, 1.0] as [CGFloat] {
            let stops = SunsetBackdrop.sky(horizon: horizon)
            #expect(stops.map(\.location) == stops.map(\.location).sorted())
            #expect(stops.contains { $0.location == horizon && HexColor.string($0.color) == "#D96654" })
            #expect(stops.last.map { HexColor.string($0.color) } == HexColor.string(ThemePalette.vice.flowTop))
        }
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
