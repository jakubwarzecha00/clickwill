import AppKit
import ClickwillModel

extension CDServices {
    /// The disc in the app: ejecting through `NSWorkspace`. With `--demo`, ripping
    /// to a temporary folder, and with `--cd-release` (and `--cd-cover`) a saved
    /// MusicBrainz response instead of the network.
    static func app(_ options: LaunchOptions) -> CDServices {
        var services = CDServices(drive: Drive(eject: { volume in
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }))
        guard options.isDemo else { return services }
        services.ripping = .demo
        if let release = options.cdRelease, let response = try? Data(contentsOf: release) {
            services.lookup = .recorded(response: response, cover: options.cdCover.flatMap { try? Data(contentsOf: $0) })
        }
        return services
    }
}
