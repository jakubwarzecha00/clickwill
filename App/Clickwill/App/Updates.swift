import SwiftUI
import Sparkle

/// Updates through Sparkle. The release feed and the public key are in Info.plist
/// (App/project.yml); Sparkle installs only releases signed with our key.
/// Only the app version is sent - nothing from the iPod or the library.
///
/// It checks for a release at every launch: releases come out often, and the Sparkle
/// schedule alone checks at most once a day. The window shows only when there is a new version. The schedule
/// (`SUScheduledCheckInterval`) stays for an app kept open longer.
///
/// A Debug build does not check on its own, so it does not offer to replace
/// the build in .build with a release from the server. `--check-updates` turns on
/// checking right after launch - for testing the whole path without clicking in the menu.
@MainActor
@Observable
final class Updates {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// Sparkle blocks a second check while the first is still running.
    private(set) var canCheck = false

    /// - Parameters:
    ///   - checkNow: checking right away, also in a Debug build (`--check-updates`).
    ///   - automated: a launch for screenshots or diagnostics - without the update window.
    init(checkNow: Bool, automated: Bool) {
        #if DEBUG
        let start = checkNow
        #else
        let start = checkNow || !automated
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: nil)
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
        if checkNow {
            Task { [controller] in
                try? await Task.sleep(for: .seconds(2))
                controller.checkForUpdates(nil)
            }
        } else if start {
            // After a moment, so the app window has time to open before any
            // update window. Sparkle skips this call when a check is already running.
            Task { [controller] in
                try? await Task.sleep(for: .seconds(2))
                if controller.updater.automaticallyChecksForUpdates {
                    controller.updater.checkForUpdatesInBackground()
                }
            }
        }
    }

    func check() {
        controller.checkForUpdates(nil)
    }
}
