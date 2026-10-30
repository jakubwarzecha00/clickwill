import SwiftUI
import ImageIO
import ClickwillModel

@main
struct ClickwillApp: App {
    @NSApplicationDelegateAdaptor(LaunchWindow.self) private var launchWindow
    @State private var model: LibraryModel
    /// Watches the connected iPod for the whole time the app runs.
    @State private var monitor: DeviceMonitor
    @State private var playback: PlaybackController
    /// Kept here, because it must live as long as the app - released, it would disappear
    /// together with the media key hookup.
    @State private var mediaControls: SystemMediaControls?
    @State private var updates: Updates
    @AppStorage(WelcomeSheet.seenKey) private var welcomeSeen = false
    /// Launch flags - read only here (`LaunchOptions`).
    private let options = LaunchOptions(arguments: CommandLine.arguments)

    /// The main window identifier - macOS remembers its size and position under it.
    static let libraryWindowID = "library"

    init() {
        // Before the window is created: otherwise it would open in the default place.
        WindowFrameMigration.run(sceneID: Self.libraryWindowID)
        // A demo copy keeps the switch and the permissions in memory: screenshots never touch the user's.
        let permissions = ExperimentalPermissions(storage: options.isDemo ? .memory() : .standard)
        permissions.developerMode = options.developerMode
        let model = LibraryModel(demo: options.demoMode, permissions: permissions)
        _model = State(initialValue: model)
        _monitor = State(initialValue: DeviceMonitor(model: model))
        _playback = State(initialValue: PlaybackController(fileURL: { [weak model] in model?.fileURL(for: $0) },
                                                           muted: options.isDemo && options.isAutomated))
        _updates = State(initialValue: Updates(checkNow: options.checksUpdates, automated: options.isAutomated))
    }

    var body: some Scene {
        // A fixed identifier: macOS remembers the window size and position under it.
        // Without it the key was the type of the whole main view, and every change to its
        // modifiers lost the remembered window.
        WindowGroup(id: Self.libraryWindowID) {
            ContentView(model: model, launch: LaunchScript(options: options))
                .environment(model)
                .environment(monitor)
                .environment(playback)
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
                .environment(\.siteURL, siteURL)
                .task {
                    monitor.start()
                    // The model and the media keys live as long as the app - the artwork takes the model directly.
                    if mediaControls == nil { mediaControls = SystemMediaControls(playback: playback, artwork: { [model] in model.artwork(for: $0) }) }
                    model.backupRetention = BackupSettings.current()
                    // Without an iPod we load nothing - the empty state stays, and `DeviceMonitor`
                    // will load the device when it appears.
                    if let source = initialSource { await model.load(source) }
                    if let output = options.iPodGallery { IPodGallery.render(to: output) }
                    if options.printsDiagnostics { Self.printDiagnostics(model: model) }
                }
        }
        .defaultSize(width: 1440, height: 900)
        // A native toolbar with the window title (macOS 27, Liquid Glass).
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // HIG: every toolbar item has a counterpart in the menu.
            CommandGroup(after: .importExport) {
                AudioCDMenu()
            }
            if AppFeatures.reorderAlbums {
                CommandGroup(after: .sidebar) {
                    WindowMenuButton(title: "Reorder Albums") { $0.showReorder() }
                        .keyboardShortcut("r", modifiers: [.command, .option])
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updates.check() }
                    .disabled(!updates.canCheck)
            }
            CommandGroup(replacing: .help) {
                WindowMenuButton(title: "Send Feedback…") { $0.showFeedback() }
                Divider()
                Button("Before You Edit Your iPod…") { welcomeSeen = false }
                WindowMenuButton(title: "Send Diagnostic Report…") { $0.showSendReport() }
            }
        }

        // The standard settings window - this is where the item in the app
        // menu and the Command-comma shortcut come from.
        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }

    /// `--snapshot <folder>` loads a backup from disk instead of a device -
    /// for development and testing without an iPod and without the risk of writing.
    private var initialSource: LibrarySource? {
        if let snapshot = options.snapshot { return .snapshot(snapshot) }
        return model.connections.preferredSource()
    }

    /// The feedback server. In Debug `--site-url <address>` points to another one, e.g. a test server.
    private var siteURL: URL {
        #if DEBUG
        if let url = options.siteURL { return url }
        #endif
        return AboutFacts.siteURL
    }
}

extension ClickwillApp {
    /// `--diagnostics` prints the diagnostic report and ends the process - the same
    /// text a tester copies from Overview. It checks a signed build
    /// (hardened runtime) without clicking: whether USB, the firmware description and the GUID
    /// are still readable.
    @MainActor
    static func printDiagnostics(model: LibraryModel) {
        print(DiagnosticsClipboard.report(model))
        exit(0)
    }
}

/// SwiftUI opens a window at launch only when the launch came from the user
/// (Finder, Dock). Launched from a script (`open` from Terminal in the background, the binary,
/// `--screen`) the app was left with just the menu, without a window. When there is no window
/// after launch, we send ourselves the same event as a click in the Dock - SwiftUI then creates it.
final class LaunchWindow: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            let reopen = NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                targetDescriptor: NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier),
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            _ = try? reopen.sendEvent(options: [.noReply], timeout: 1)
            NSApp.activate()
        }
    }
}

/// A menu item that asks the active window for a screen or a sheet (`WindowState`).
private struct WindowMenuButton: View {
    let title: String
    let action: (WindowState) -> Void
    @FocusedValue(\.window) private var window

    var body: some View {
        Button(title) { if let window { action(window) } }
            .disabled(window == nil)
    }
}
