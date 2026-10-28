import SwiftUI

/// Facts about the app: the name, version and stage from Info.plist (renaming the
/// product needs no code changes), the feedback server and the data for the
/// About panel. Placeholders to fill in before publishing are here.
enum AboutFacts {
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "This app"
    }
    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }
    /// The release stage from Info.plist (`ClickwillReleaseStage`): "alpha", "beta"
    /// or `nil` in version 1.0 and later.
    static var stage: String? {
        (Bundle.main.object(forInfoDictionaryKey: "ClickwillReleaseStage") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    /// The alpha is given away for free - without a purchase there is no "amount you paid".
    static var isFree: Bool { stage == "alpha" }
    /// "this alpha", "this beta" or "this version" - for sentences in the interface.
    static var thisVersion: String { "this \(stage ?? "version")" }
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    /// The Clickwill server from Info.plist (`ClickwillSiteURL`).
    static var siteURL: URL {
        let value = Bundle.main.object(forInfoDictionaryKey: "ClickwillSiteURL") as? String ?? ""
        return URL(string: value) ?? URL(string: "https://clickwilldev.com")!
    }
}

extension EnvironmentValues {
    /// The server that accepts reports. In Debug, `ClickwillApp` can give
    /// a different one (`--site-url <address>`), e.g. a test server on the local network.
    @Entry var siteURL: URL = AboutFacts.siteURL
}

extension AboutFacts {
    /// The address for reports (Proton Mail).
    static let supportEmail: String? = "clickwilldev@protonmail.com"
    static let author = "Jakub Warzecha"
    static let year = "2026"

    /// The public source code of the app - the GPL asks for a way to get it.
    static let sourceURL = URL(string: "https://github.com/jakubwarzecha00/clickwill")!

    /// LICENSE from the repository root (GNU GPL version 3), bundled with the app.
    static var license: String { bundledText("LICENSE", missing: "The license file is missing from this build.") }

    /// THIRD-PARTY-NOTICES from the repository root, bundled with the app.
    static var thirdPartyNotices: String {
        bundledText("THIRD-PARTY-NOTICES", missing: "Third-party notices file is missing from this build.")
    }

    private static func bundledText(_ name: String, missing: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return missing }
        return text
    }
}
