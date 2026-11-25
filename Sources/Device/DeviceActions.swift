import SwiftUI

/// What the Device screens ask the app to do. The module knows nothing about the window,
/// the sheets or the player: the app sets these once (`App/Clickwill/Shell/Modules.swift`).
public struct DeviceActions: Sendable {
    /// Opens Diagnostics of the loaded iPod.
    public var runDiagnostics: @MainActor @Sendable () -> Void
    /// Opens Send Diagnostic Report, with the comment filled in.
    public var sendReport: @MainActor @Sendable (_ comment: String) -> Void
    public var sendFeedback: @MainActor @Sendable () -> Void
    /// Before a backup is restored: the player may hold a file from the iPod, as when ejecting.
    public var stopPlayback: @MainActor @Sendable () -> Void

    public init(runDiagnostics: @escaping @MainActor @Sendable () -> Void,
                sendReport: @escaping @MainActor @Sendable (_ comment: String) -> Void,
                sendFeedback: @escaping @MainActor @Sendable () -> Void,
                stopPlayback: @escaping @MainActor @Sendable () -> Void) {
        self.runDiagnostics = runDiagnostics
        self.sendReport = sendReport
        self.sendFeedback = sendFeedback
        self.stopPlayback = stopPlayback
    }

    /// Until the app sets them: every button does nothing.
    static let none = DeviceActions(runDiagnostics: {}, sendReport: { _ in }, sendFeedback: {}, stopPlayback: {})
}

public extension EnvironmentValues {
    @Entry var deviceActions: DeviceActions = .none
}
