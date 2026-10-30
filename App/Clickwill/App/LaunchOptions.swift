import Foundation
import ClickwillModel

/// The app's launch flags - the only place that understands them.
///
/// All of them serve screenshots, website recordings, tests and diagnostics;
/// a normal launch has none. `ClickwillApp` reads the process arguments once
/// and hands out what follows from them: demo mode to the model, `LaunchScript`
/// to the window, update settings to `Updates`. The views do not know the flags.
struct LaunchOptions: Sendable {
    let arguments: [String]

    func has(_ flag: String) -> Bool { arguments.contains(flag) }

    /// The value after a flag (`--flag value`).
    func value(_ flag: String) -> String? {
        arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
    }

    /// All values of a flag given several times.
    func values(_ flag: String) -> [String] {
        arguments.indices.dropLast().filter { arguments[$0] == flag }.map { arguments[$0 + 1] }
    }

    private func file(_ flag: String) -> URL? { value(flag).map { URL(fileURLWithPath: $0) } }

    // MARK: - Demo mode and source

    /// `--demo`: website recordings and tests on a real iPod - nothing
    /// reaches the iPod, discs are ripped to a temporary folder. Playback
    /// is silent only on an automated launch (`isAutomated`: screenshots,
    /// recordings) - when clicking by hand, sound plays as usual.
    var isDemo: Bool { has("--demo") }

    /// Demo mode for the model (`DemoMode`).
    ///
    /// - `--demo --snapshot <demo library>`: screenshots and ads (a library
    ///   built with `ipodctl demo-snapshot`); the backup shown as an iPod described by `--demo-device`
    ///   ("iPod classic · 160 GB" by default).
    /// - `--demo-ipod "<backup>|<name>|<model>|<GB>|<GB used>"` (several times):
    ///   connected iPods for the chooser, without two devices.
    var demoMode: DemoMode {
        guard isDemo else { return .off }
        var mode = DemoMode(blocksWrites: true)
        guard has("--snapshot") else { return mode }
        mode.deviceDetail = value("--demo-device") ?? "iPod classic · 160 GB"
        mode.choices = values("--demo-ipod").compactMap(IPodChoice.init(demoArgument:))
        return mode
    }

    /// `--snapshot <folder>`: a backup from disk instead of a device - for development
    /// and testing without an iPod and without the risk of writing.
    var snapshot: URL? { file("--snapshot") }

    // MARK: - Screen after launch

    /// The screen after the library loads (`--screen …`).
    enum Screen: String, Sendable {
        case coverflow, albums, album, reorder, songs, overview, backups, pending
        /// The change list with a sample post-write report.
        case writeReport = "write-report"
        /// Diagnostics and the Rockbox report with a sample iPod Video (`SampleDiagnostics`).
        case diagnostics, rockbox
        /// Send Diagnostic Report over the sample Diagnostics.
        case sendReport = "send-report"
        /// The warning before Developer Mode (`ExperimentalConsent.askDeveloperMode`).
        case developerMode = "developer-mode"
    }

    /// `--screen coverflow|albums|album|reorder|songs|overview|backups|pending|write-report|diagnostics|rockbox|send-report|developer-mode`.
    /// An unknown name is `nil` - a normal launch.
    var screen: Screen? { value("--screen").flatMap(Screen.init(rawValue:)) }
    /// `--centered N`: the album in the middle of the strip (with `--screen albums` - of the wheel).
    var centered: Int? { value("--centered").flatMap(Int.init) }
    /// `--center <title or artist>`.
    var center: String? { value("--center") }
    /// `--loop-from <album> --loop-to <album>`: a Cover Flow loop for a video.
    var coverFlowLoop: (from: String, to: String)? {
        guard let from = value("--loop-from"), let to = value("--loop-to") else { return nil }
        return (from, to)
    }
    /// `--editor`: the album edit panel open right away.
    var showsAlbumEditor: Bool { has("--editor") }

    // MARK: - Data for screenshots

    /// `--import <path>`: the add sheet with these files after the library loads.
    var importURL: URL? { file("--import") }
    /// `--import-after <s>`: after this many seconds.
    var importDelay: Double { value("--import-after").flatMap(Double.init) ?? 0 }
    /// `--demo-cover <image>`: "Change Cover…" takes this file instead of the panel.
    var demoCover: URL? { file("--demo-cover") }
    /// `--audio-cd <folder with a .TOC.plist>`: the disc screen without a drive.
    var audioCDFixture: URL? { file("--audio-cd") }
    /// `--cd-release <response.json>`: a disc lookup result without the network.
    var cdRelease: URL? { file("--cd-release") }
    /// `--cd-cover <image>`: the artwork for that result.
    var cdCover: URL? { file("--cd-cover") }

    // MARK: - With nobody at the screen

    /// `--ipod-gallery <file.png>`: drawings of all iPods, then quit.
    var iPodGallery: URL? { file("--ipod-gallery") }
    /// `--diagnostics`: the diagnostic report to the output, then quit.
    var printsDiagnostics: Bool { has("--diagnostics") }

    /// `--developer-mode`: Developer Mode from launch, without the warning
    /// (`ExperimentalPermissions.developerMode`). Only a Debug build reads the flag; a release
    /// turns Developer Mode on only in Settings, after the warning.
    var developerMode: Bool {
        #if DEBUG
        has("--developer-mode")
        #else
        false
        #endif
    }
    /// A launch for screenshots or diagnostics - nobody is sitting at the screen.
    var isAutomated: Bool { has("--diagnostics") || has("--screen") }
    /// `--check-updates`: checking for updates also in a Debug build.
    var checksUpdates: Bool { has("--check-updates") }
    /// `--site-url <address>` (Debug only): another Clickwill server, e.g. a test server.
    var siteURL: URL? { value("--site-url").flatMap(URL.init(string:)) }
}
