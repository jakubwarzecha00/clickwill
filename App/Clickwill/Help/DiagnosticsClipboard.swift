import AppKit
import ClickwillModel
import ITDBKit

/// The diagnostic report as text - for Send Diagnostic Report, Send Feedback and `--diagnostics`.
/// What is in the report, and what is deliberately not - `DiagnosticReport`.
enum DiagnosticsClipboard {
    @MainActor
    static func report(_ model: LibraryModel, album: String? = nil, diagnostics: Diagnostics? = nil) -> String {
        DiagnosticReport.text(for: model, appVersion: AboutFacts.version + (AboutFacts.stage.map { " \($0)" } ?? ""),
                              system: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                              hardware: hardwareModel, album: album, diagnostics: diagnostics)
    }

    /// E.g. `Mac16,10`. A model identifier, not a unit's.
    static var hardwareModel: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
