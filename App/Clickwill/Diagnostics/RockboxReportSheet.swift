import SwiftUI
import AppKit
import ClickwillModel
import ITDBKit

/// Albums that look different in Rockbox (`RockboxReport`). Reads every song file, so it
/// runs on demand with a progress bar. Read-only; technical wording.
struct RockboxReportSheet: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sampleDiagnostics) private var sample
    @State private var report: RockboxReport?
    @State private var progress: (done: Int, total: Int) = (0, 0)
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Rockbox reads tags from audio files, not iTunesDB. Albums whose file tags differ from the iPod library:")
                        .foregroundStyle(.secondary)
                }
                if let report {
                    if report.albums.isEmpty {
                        Section { Label("No differences in \(report.scannedTracks) files.", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok) }
                    } else {
                        Section("\(report.albums.count) albums · \(report.scannedTracks) files read · Rockbox \(report.installation.version ?? "")") {
                            ForEach(report.albums) { album in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(album.title ?? "(no album)")
                                    ForEach(album.issues, id: \.self) { issue in
                                        Text(issue.detail).font(.theme(.footnote)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                            Text("Reading files…")
                        } currentValueLabel: {
                            Text("\(progress.done) of \(progress.total)").monospacedDigit()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("How This Library Looks in Rockbox")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copied ? "Copied" : "Copy Report") { copy() }.disabled(report == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 440, idealHeight: 560)
        .task {
            if let sample { report = sample.rockboxReport; return }
            report = await model.rockboxReport { done, total in
                Task { @MainActor in progress = (done, total) }
            }
        }
    }

    private func copy() {
        guard let report else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.reportLines.joined(separator: "\n"), forType: .string)
        copied = true
    }
}
