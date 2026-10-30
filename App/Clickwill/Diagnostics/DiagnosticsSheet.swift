import SwiftUI
import AppKit
import ClickwillModel
import ITDBKit

/// Diagnostics of the loaded iPod: every check, grouped as in `Diagnostics`, the way to
/// experimental writing when the model isn't confirmed but every required check passed, and
/// Send Diagnostic Report over it (`SendReportSheet`).
/// Technical wording, without the first person.
struct DiagnosticsSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sampleDiagnostics) private var sample
    @Environment(\.siteURL) private var siteURL
    @State private var result: Diagnostics?
    @State private var checked = false
    @State private var failure: String?
    @State private var sending: SendRequest?

    /// `sendComment` opens Send Diagnostic Report as soon as the checks are done.
    init(sendComment: String? = nil) {
        _sending = State(initialValue: sendComment.map(SendRequest.init))
    }

    private struct SendRequest: Identifiable {
        let id = UUID()
        let comment: String
    }

    /// On an unconfirmed or read-only model the report is what's needed, so Send Report is the
    /// prominent button. In the summary, not the bottom bar: a sheet shows one confirmation
    /// button there, and Allow Experimental Writing takes it.
    private var sendIsPrimary: Bool { result.map { !$0.confirmedModel } ?? true }

    @ViewBuilder private var sendButton: some View {
        let button = Button("Send Report…") { sending = SendRequest(comment: "") }
        if sendIsPrimary { button.buttonStyle(.borderedProminent) } else { button }
    }

    private var experimentalEnabled: Bool { model.permissions.isEnabled }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    Section {
                        Text(summary(result)).font(.theme(.row, weight: .semibold))
                        Text(explanation(result)).foregroundStyle(.secondary)
                        HStack {
                            sendButton
                            Spacer()
                        }
                    }
                    ForEach(Diagnostics.Group.allCases, id: \.self) { group in
                        let checks = result.checks.filter { $0.group == group }
                        if !checks.isEmpty {
                            Section(Self.title(group)) {
                                ForEach(checks) { CheckRow(check: $0) }
                            }
                        }
                    }
                    if !result.measurements.isEmpty {
                        Section {
                            Text(result.measurements.joined(separator: "\n"))
                                .font(.theme(.footnote, design: .monospaced)).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } header: {
                            Text("Measurements")
                        } footer: {
                            Text("Sent with the report. Record layouts, settings and counts only: no GUID, serial number, titles or folder names.")
                        }
                    }
                    if let rockbox = model.rockbox ?? sample?.rockbox {
                        Section("Rockbox") {
                            LabeledContent("Rockbox \(rockbox.version ?? "")") {
                                Button("Show Albums…") { window.showRockboxReport(); dismiss() }
                            }
                            Text("Rockbox reads tags from audio files, not iTunesDB. Read-only report.")
                                .font(.theme(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    if let sync = model.onDeviceSync {
                        Section("Library Sync on the iPod") {
                            LabeledContent("Firmware with its own sync", value: sync.stateVersion.map { "state version \($0)" } ?? "no sync yet")
                            Text("The firmware rebuilds iTunesDB from /Music at boot and after every USB session. Songs added under iPod_Control stay. FLAC songs and videos outside iPod_Control follow their files: removal and cover changes are refused for them.")
                                .font(.theme(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    if let failure {
                        Section { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn) }
                    }
                } else if checked {
                    Section {
                        Text("No iPod loaded.").font(.theme(.row, weight: .semibold))
                        Text("The report covers Clickwill and this Mac only.").foregroundStyle(.secondary)
                        HStack {
                            sendButton
                            Spacer()
                        }
                    }
                } else {
                    Section { ProgressView("Checking…").frame(maxWidth: .infinity) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if result?.allowsExperimentalWriting == true, model.device?.writePolicy != .experimental {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Allow Experimental Writing…") { allow() }
                            .disabled(!experimentalEnabled)
                            .help(experimentalEnabled ? "" : "Requires Settings › Experimental iPods.")
                    }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 640)
        .task {
            result = sample?.diagnostics ?? model.runDiagnostics()
            checked = true
        }
        .sheet(item: Binding(get: { checked ? sending : nil }, set: { sending = $0 })) { request in
            SendReportSheet(diagnostics: result, comment: request.comment)
                .environment(model).environment(\.siteURL, siteURL).foregroundStyle(Theme.fg)
        }
    }

    private func summary(_ result: Diagnostics) -> String {
        if result.confirmedModel { return "Confirmed model. Writing allowed." }
        if model.device?.writePolicy == .experimental { return "Experimental writing allowed for this iPod." }
        if result.allowsExperimentalWriting { return "All required checks passed." }
        let failed = result.checks.filter { $0.weight == .required && $0.status != .passed }
        return "Read-only. \(failed.count) required \(failed.count == 1 ? "check" : "checks") failed."
    }

    private func explanation(_ result: Diagnostics) -> String {
        if result.confirmedModel { return "Diagnostics are informational on confirmed models." }
        if result.allowsExperimentalWriting {
            return experimentalEnabled
                ? "Experimental writing available: editing, adding and deleting songs. New artwork only in measured formats."
                : "Experimental writing requires Settings › Experimental iPods."
        }
        if !result.unsigned { return "Experimental writing covers unsigned databases only (pre-2007 iPods)." }
        return "Experimental writing requires every required check to pass."
    }

    private func allow() {
        guard ExperimentalConsent.ask(modelName: model.device?.model.name ?? "this iPod") else { return }
        Task {
            do {
                try await model.allowExperimentalWriting()
                result = model.runDiagnostics()
                failure = nil
            } catch {
                failure = "Not allowed: \(error)"
            }
        }
    }

    static func title(_ group: Diagnostics.Group) -> String {
        switch group {
        case .device: "Device"
        case .library: "Library"
        case .files: "Files"
        case .artwork: "Artwork"
        case .disk: "Disk and Mac"
        }
    }
}

/// One check: a symbol for the status, the name, the technical detail, the weight.
private struct CheckRow: View {
    let check: Diagnostics.Check

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.name(check.id))
                Text(check.detail).font(.theme(.footnote)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text(check.weight == .required ? "Required" : "Advisory")
                .font(.theme(.caption)).foregroundStyle(.tertiary)
        }
    }

    private var symbol: String {
        switch check.status {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .info: "info.circle"
        }
    }

    private var color: Color {
        switch check.status {
        case .passed: Theme.ok
        case .warning: Theme.warn
        case .failed: Theme.destructive
        case .info: .secondary
        }
    }

    static func name(_ id: Diagnostics.Check.ID) -> String {
        switch id {
        case .usb: "USB"
        case .firmwareDescription: "Firmware description"
        case .identity: "Identity"
        case .format: "Database format"
        case .rebuild: "Byte-for-byte rebuild"
        case .playCounts: "Pending plays"
        case .files: "Files"
        case .artwork: "ArtworkDB"
        case .volume: "Volume"
        case .music: "Music"
        }
    }
}
