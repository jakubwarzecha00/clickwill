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

    /// The sky is one unbroken gradient: the palette's horizon color sits on the horizon,
    /// wherever it is, and the bottom edge is the plum of the bar under the slider.
    @Test func theSkyMeetsTheHorizonAndTheBarUnderTheSlider() {
        let vice = ThemePalette.vice
        for horizon in [0.6, 0.7, 1.0] as [CGFloat] {
            let stops = SunsetSky.stops(horizon: horizon)
            #expect(stops.map(\.location) == stops.map(\.location).sorted())
            #expect(stops.contains { $0.location == horizon && HexColor.string($0.color) == HexColor.string(vice.flowBottom) })
            #expect(stops.last.map { HexColor.string($0.color) } == HexColor.string(vice.flowTop))
            #expect(HexColor.string(vice.floorBottom) == HexColor.string(vice.flowTop))
        }
    }

    /// Album titles stand in the upper part of the sky; every color there reads with white.
    @Test func titlesReadOnTheUpperSky() {
        let vice = ThemePalette.vice
        for stop in SunsetSky.stops(horizon: 0.65) where stop.location <= 0.65 * 0.35 {
            #expect(ThemeContrast.ratio(vice.sceneText, on: stop.color) >= 4.5)
        }
    }

    @Test func everyPalmIsInTheBundle() {
        for palm in PalmSilhouette.allCases {
            #expect(palm.image != nil, "\(palm.rawValue) is missing")
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
