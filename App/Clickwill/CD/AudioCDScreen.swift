import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClickwillModel

/// Disc commands from the toolbar and the File menu.
enum AudioCDCommand: String { case lookUp, pasteTrackList, importCD, eject }

/// The commands of the disc screen on top - the File menu calls them directly, and without
/// a disc screen (`nil`) its items are disabled.
struct AudioCDCommands {
    let perform: (AudioCDCommand) -> Void
}

struct AudioCDCommandsKey: FocusedValueKey { typealias Value = AudioCDCommands }

extension FocusedValues {
    var audioCD: AudioCDCommands? {
        get { self[AudioCDCommandsKey.self] }
        set { self[AudioCDCommandsKey.self] = newValue }
    }
}

/// The screen of the disc in the drive: names (from MusicBrainz, the clipboard or typed in),
/// the format and ripping. Ripped files go to the Add Songs dialog, so the disc
/// goes through the same duplicate check as any other album.
struct AudioCDScreen: View {
    @Bindable var session: CDSession
    @Environment(LibraryModel.self) private var model
    @Environment(WindowState.self) private var window
    @State private var preview = PreviewPlayer()
    @State private var pasteProblem: String?

    var body: some View {
        Form {
            // Footers in the secondary color explicitly: the window imposes Theme.fg on all texts.
            Section { header.disabled(session.isRipping) } footer: { lookupStatus.foregroundStyle(.secondary) }
            Section {
                ForEach($session.draft.songs) { $song in songRow($song) }
            } header: {
                HStack {
                    Text("Songs")
                    Spacer()
                    Button("Paste Track List") { paste() }
                        .controlSize(.small)
                        .disabled(session.isRipping)
                        .help("Copy a list of song titles, one per line, from anywhere. Clickwill fills them in order.")
                }
            }
            Section { formatPicker.disabled(session.isRipping) } header: { Text("Format") } footer: { importNote.foregroundStyle(.secondary) }
            if let outcome = session.outcome, !outcome.failed.isEmpty { failures(outcome) }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .defaultScrollAnchor(.top)
        .onDisappear { preview.stop() }
        .toolbar { toolbarContent }
        .focusedSceneValue(\.audioCD, AudioCDCommands(perform: perform))
        .alert("Paste Track List", isPresented: Binding(get: { pasteProblem != nil }, set: { if !$0 { pasteProblem = nil } })) {
            Button("OK", role: .cancel) { pasteProblem = nil }
        } message: { Text(pasteProblem ?? "") }
        .alert("Preview", isPresented: Binding(get: { preview.errorMessage != nil },
                                               set: { if !$0 { preview.errorMessage = nil } })) {
            Button("OK", role: .cancel) { preview.errorMessage = nil }
        } message: { Text(preview.errorMessage ?? "") }
    }

    func perform(_ command: AudioCDCommand) {
        switch command {
        case .lookUp: Task { await session.lookUp() }
        case .pasteTrackList: paste()
        case .importCD: importCD()
        case .eject: preview.stop(); session.eject()
        }
    }

    private func paste() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        switch session.pasteTrackList(text) {
        case .filled:
            pasteProblem = nil
        case .noTrackList:
            pasteProblem = "The clipboard has no track list. Copy the list of songs first, one per line."
        case .countMismatch(let lines, let songs):
            pasteProblem = "The clipboard has \(lines) \(lines == 1 ? "line" : "lines"), but this CD has \(songs) songs. Nothing was changed."
        }
    }

    private func chooseCover() {
        guard let url = FilePanels.chooseImage(message: "Choose the album cover.") else { return }
        session.setCover(from: url)
    }

    private func importCD() {
        preview.stop()
        session.rip { files in
            // Without an iPod the files stay on the Mac; they are added later through Add Songs.
            guard model.isWritable else { return }
            window.showImport(files)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        // Symbols alone in one group, and the text Import CD separately and as
        // the only prominent one (HIG, Toolbars).
        ToolbarItemGroup(placement: .primaryAction) {
            Button { perform(.lookUp) } label: { Label("Look Up Online", systemImage: "text.magnifyingglass") }
                .help("Look Up Online: finds the song names in MusicBrainz. Sends only this CD's ID.")
                .disabled(session.isRipping || session.lookup == .looking)
            Button { perform(.eject) } label: { Label("Eject Disc", systemImage: "eject") }
                .help("Eject Disc")
        }
        ToolbarItem(placement: .confirmationAction) {
            if session.isRipping {
                Button("Stop") { session.cancelRip() }
            } else {
                // Prominent only after the lookup - before it the first step
                // is Look Up Online on the disc screen.
                if session.needsLookUp {
                    Button("Import CD") { perform(.importCD) }
                        .disabled(session.draft.missing != nil)
                        .help(session.draft.missing ?? "Import the checked songs to this Mac, then add them to your iPod.")
                } else {
                    Button("Import CD") { perform(.importCD) }
                        .prominentGlassButtonStyle()
                        .disabled(session.draft.missing != nil)
                        .help(session.draft.missing ?? "Import the checked songs to this Mac, then add them to your iPod.")
                }
            }
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            cover
            VStack(alignment: .leading, spacing: 6) {
                ImportField(text: $session.draft.album, placeholder: "Add album name", font: .title2.weight(.semibold))
                ImportField(text: $session.draft.albumArtist, placeholder: "Add album artist", font: .title3)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ImportField(text: $session.draft.year, placeholder: "Year", font: .body.monospacedDigit(), width: 52)
                    ImportField(text: $session.draft.genre, placeholder: "Genre", font: .body, width: 160)
                    Toggle("Compilation", isOn: $session.draft.isCompilation)
                        .toggleStyle(.checkbox)
                        .help("Compilations sit together at the end of Cover Flow on the iPod.")
                    if session.draft.totalDiscs > 1 {
                        Text("Disc \(session.draft.discNumber) of \(session.draft.totalDiscs)")
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.secondary)
                Text("\(session.draft.songs.count) songs · \(Self.time(UInt64(session.disc.duration * 1000)))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    .padding(.top, 2)
                // The first step as the only prominent button on the screen -
                // a small button in the footer blended in with the rest. Import CD gets
                // prominence only after the lookup.
                if session.needsLookUp {
                    HStack(spacing: 10) {
                        Button { Task { await session.lookUp() } } label: {
                            Label("Look Up Online", systemImage: "text.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text("Fills in the song names, year, genre and cover.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var cover: some View {
        Button { chooseCover() } label: {
            Group {
                if let data = session.draft.cover, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "opticaldisc")
                        .font(.symbol(.placeholderLarge, weight: .light))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.fill.tertiary)
                }
            }
            .frame(width: 132, height: 132)
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Choose a cover image, or drop one here.")
        // A file that is not an image changes nothing (`CDSession.setCover`).
        .dropDestination(for: URL.self) { urls, _ in
            // The version returning Bool - the one without a result exists only from macOS 26.
            guard let url = urls.first else { return false }
            session.setCover(from: url)
            return true
        }
    }

    @ViewBuilder private var lookupStatus: some View {
        switch session.lookup {
        case .idle:
            // A button on the screen, not just the magnifier in the corner of the bar: with a disc
            // that had names nobody looked for it, and the year, genre and artwork stayed
            // empty.
            Text(session.disc.hasTitle
                 ? "Song names come from the disc. Look Up Online sends MusicBrainz only this CD's ID, worked out from the track lengths."
                 : "This CD carries no song names. Look them up online, paste a track list, or type them in. Look Up Online sends MusicBrainz only this CD's ID.")
        case .looking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Looking up this CD in MusicBrainz…") }
        case .found:
            if session.releases.count > 1 {
                Picker("Edition", selection: Binding(
                    get: { session.draft.releaseID ?? "" },
                    set: { id in
                        if let release = session.releases.first(where: { $0.id == id }) {
                            Task { await session.choose(release) }
                        }
                    })) {
                    ForEach(session.releases) { release in
                        Text("\(release.title) · \(release.summary)").tag(release.id)
                    }
                }
                .fixedSize()
            } else if let release = session.selectedRelease {
                Text("Found in MusicBrainz: \(release.title) · \(release.summary)")
            }
        case .notFound:
            Text("MusicBrainz doesn't know this CD yet. Paste a track list or type the names, and choose a cover.")
        case .failed(let failure):
            HStack(spacing: 8) {
                Text(Self.message(failure))
                Button("Try Again") { Task { await session.lookUp() } }.controlSize(.small)
            }
        }
    }

    private func songRow(_ song: Binding<CDDraft.Song>) -> some View {
        let value = song.wrappedValue
        let id = session.previewIDs[value.number] ?? UUID()
        return HStack(spacing: 10) {
            Toggle("Include", isOn: song.included).toggleStyle(.checkbox).labelsHidden()
                .help("Import this song")
                .disabled(session.isRipping)
            if let file = value.file {
                PreviewButton(id: id, url: file, preview: preview)
            }
            Text("\(value.number)").monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                ImportField(text: song.title, placeholder: "Add title")
                ImportField(text: song.artist, placeholder: session.draft.albumArtist.isEmpty ? "Add artist" : session.draft.albumArtist,
                            font: .subheadline, width: 260)
                    .foregroundStyle(.secondary)
                if preview.isLoaded(id) { PreviewScrubber(id: id, preview: preview).padding(.top, 2) }
            }
            .opacity(value.included ? 1 : 0.45)
            .disabled(session.isRipping)
            Spacer(minLength: 8)
            ripState(value)
            Text(Self.time(UInt64(value.durationMilliseconds))).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func ripState(_ song: CDDraft.Song) -> some View {
        let included = session.draft.includedSongs.map(\.number)
        if session.ripped.contains(song.number) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Imported")
        } else if let ripping = session.ripping, included.indices.contains(ripping.index), included[ripping.index] == song.number {
            ProgressView(value: ripping.fraction).frame(width: 80)
        }
    }

    private var formatPicker: some View {
        Picker("Import as", selection: $session.format) {
            ForEach(CDRipper.Format.allCases) { format in
                VStack(alignment: .leading) {
                    Text(format.label)
                    Text("\(format.detail) About \(Self.size(format.estimatedBytes(milliseconds: session.includedMilliseconds))).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .tag(format)
            }
        }
        .pickerStyle(.radioGroup)
    }

    @ViewBuilder private var importNote: some View {
        let folder = CDRipper.folder(for: session.draft)
        VStack(alignment: .leading, spacing: 6) {
            if let outcome = session.outcome, !outcome.files.isEmpty, !session.isRipping {
                HStack(spacing: 8) {
                    Text(model.isWritable
                         ? "Imported \(outcome.files.count) songs to this Mac."
                         : "Imported \(outcome.files.count) songs to this Mac. Connect your iPod, then add them with Add Songs or Albums.")
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(outcome.files) }
                        .controlSize(.small)
                }
            }
            Text("Songs are saved on this Mac first, in Music › Clickwill › \(folder.deletingLastPathComponent().lastPathComponent) › \(folder.lastPathComponent). You can eject the CD before anything goes to your iPod. Nothing is written to the iPod until you click Write to iPod.")
            if let missing = session.draft.missing { Text(missing).foregroundStyle(.orange) }
        }
    }

    private func failures(_ outcome: CDRipper.Outcome) -> some View {
        Section("Not Imported") {
            ForEach(Array(outcome.failed.enumerated()), id: \.offset) { _, failure in
                Label(ErrorPresenter.line(failure), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Text("A scratched disc often reads on a second try. Clean it, then click Import CD again.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    static func message(_ failure: CDSession.LookupFailure) -> String {
        switch failure {
        case .unreachable: return "Couldn't reach MusicBrainz. Check your internet connection and try again."
        case .badAnswer(let error): return ErrorPresenter.message(for: error)
        }
    }

    static func time(_ milliseconds: UInt64) -> String {
        let seconds = Int(milliseconds / 1000)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Disc commands in the File menu - active when its screen is on top.
struct AudioCDMenu: View {
    @FocusedValue(\.audioCD) private var commands

    var body: some View {
        Divider()
        Button("Look Up CD Online") { commands?.perform(.lookUp) }.disabled(commands == nil)
        Button("Paste Track List") { commands?.perform(.pasteTrackList) }.disabled(commands == nil)
        Button("Import CD") { commands?.perform(.importCD) }.disabled(commands == nil)
        Button("Eject Disc") { commands?.perform(.eject) }.disabled(commands == nil)
            .keyboardShortcut("e", modifiers: .command)
    }
}
