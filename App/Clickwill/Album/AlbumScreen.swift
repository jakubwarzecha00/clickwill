import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClickwillModel
import ITDBKit

/// The album screen: a header with the artwork, a track list with dragging and removal, an inspector.
struct AlbumScreen: View {
    @Environment(LibraryModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    let album: AlbumCard
    /// The image "Change Cover…" takes instead of the file choose panel -
    /// in a demo recording the panel would be unreadable (`LaunchScript.coverFile`).
    let coverFile: URL?
    /// The album disappears together with the screen - after a deletion there is nothing to go back to.
    let onDeleted: () -> Void
    @State private var selection: Set<UInt32> = []
    @FocusState private var listFocused: Bool
    @State private var error: String?
    /// In-place editing: which row and which field.
    @State private var editing: RowEdit?
    /// The edit panel is hidden until the user opens it -
    /// most of the time one looks at the tracks, not at fields to correct.
    /// Open right away only in screenshots (`LaunchScript.opensAlbumEditor`).
    @State private var editorShown: Bool
    /// The dialog for restoring files for entries that have no file.
    @State private var missingFilesShown = false

    enum RowEdit: Equatable { case title(UInt32), number(UInt32) }

    init(album: AlbumCard, editorShown: Bool = false, coverFile: URL? = nil, onDeleted: @escaping () -> Void = {}) {
        self.album = album
        self.coverFile = coverFile
        self.onDeleted = onDeleted
        _editorShown = State(initialValue: editorShown)
    }

    /// The card refreshed after an edit - the one from `screen` may already be stale.
    /// When the album no longer exists (deleted), the last known one stays.
    private var current: AlbumCard { model.current(album) ?? album }
    private var image: CGImage? { model.artwork(for: current.artworkTrackID) }
    private var tint: Color { image.map(DominantColor.of) ?? Theme.accent }
    /// Songs the iPod's own library sync rebuilds from their files: no removal, no new cover.
    private var synced: Bool { model.isSyncedOnDevice(current) }

    /// One curve for opening and closing the panel, from every place.
    static let editorAnimation = Animation.smooth(duration: 0.32)

    var body: some View {
        // The album's tracks once per draw - the list, the header, the format notice
        // and the menu of every row get the same array.
        let rows = model.tracks(of: current)
        HStack(spacing: 10) {
            trackList(rows)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Under the whole view (header and list): the artwork centered,
            // filling edge to edge (cropped), blurred; at the top
            // darkened moderately, under the list more, so the rows
            // stay readable.
            .background { backdrop }
            // The top part of the gradient takes the artwork's dominant color; without artwork
            // the theme accent remains.
            .background(LinearGradient(colors: [tint.opacity(0.42), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
            .animation(.easeOut(duration: 0.35), value: current.artworkTrackID)
            // Sharp background corners stood out against the rounded panels in the rest of the window.
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelCorner))
            // A panel in the album layout, not the system `.inspector`: that one shared the width
            // of the window with the sidebar and hid it for a moment when opening. It looks
            // like an inspector: a grouped Form on the scene background.
            if editorShown {
                inspector
                    .scrollContentBackground(.hidden)
                    .frame(width: Theme.inspectorWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 4, trailing: 10))
        .background(Theme.stage)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editorShown ? "Hide Editor" : "Show Editor", systemImage: "sidebar.right") {
                    withAnimation(Self.editorAnimation) { editorShown.toggle() }
                }
                .help(editorShown ? "Hide the album editor" : "Edit the album's details and cover")
            }
        }
        .task(id: current.artworkTrackID) { await model.ensureArtwork(for: current.artworkTrackID) }
        .onChange(of: album.id, initial: true) { model.prioritizeFormatCheck(of: album) }
        .sheet(isPresented: $missingFilesShown) {
            MissingFilesSheet(album: current).environment(model)
        }
        .alert("This change couldn't be made", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private var backdrop: some View {
        if let image { AlbumBackdrop(image: image, id: current.artworkTrackID) }
    }

    private func header(_ rows: [TrackRow]) -> some View {
        HStack(alignment: .bottom, spacing: 26) {
            // Artwork is changed only in the Edit panel. In the header it is just
            // the image - no hover, no dropping and no context menu.
            artwork
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.34), radius: 11, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(current.displayTitle).font(.theme(.largeTitle, weight: .bold)).lineLimit(2)
                Text(current.displayArtist).font(.theme(.title2, weight: .medium)).foregroundStyle(Theme.accent)
                Text(meta).font(.theme(.row)).foregroundStyle(Theme.f2).monospacedDigit()
                HStack(spacing: 9) {
                    // The album's main action: a larger system button in the accent color
                    // (blue by default) - a dimmed pill did not look
                    // clickable.
                    Button {
                        playback.play(rows, startingAt: nil, in: current)
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.theme(.row, weight: .semibold))
                            .padding(.horizontal, 10)
                    }
                    .prominentGlassButtonStyle()
                    .tint(.accentColor)
                    .controlSize(.extraLarge)
                    .disabled(rows.isEmpty)
                    albumMenu
                    if current.isCompilation { compilationBadge }
                    if synced { syncedBadge }
                    if current.missingFiles > 0 { missingFilesButton }
                    Spacer()
                }.padding(.top, 6)
            }
            .padding(.bottom, 4)
        }
        .padding(EdgeInsets(top: 26, leading: 24, bottom: 20, trailing: 24))
    }

    /// Entries without a file. Until now this was just information nothing could
    /// be done with - now it leads to a dialog in which a file can be given
    /// a source on the Mac.
    private var missingFilesButton: some View {
        Button { missingFilesShown = true } label: {
            Label("\(current.missingFiles) without a file", systemImage: "questionmark.folder")
                .font(.theme(.body, weight: .medium)).foregroundStyle(Theme.warn)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Theme.warn.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Point these entries at their audio files")
    }

    /// Just information, not a warning. For a movie soundtrack the flag is
    /// right, for a badly tagged album it is not - and the flag alone cannot
    /// settle that. Clearing it sits under the three dots, so the library
    /// cannot be changed with one accidental click.
    private var compilationBadge: some View {
        Label("Tagged “Various Artists”", systemImage: "person.2")
            .font(.theme(.body, weight: .medium)).foregroundStyle(Theme.f2)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.row, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.glassBorder, lineWidth: 0.5))
            .help("The songs of this album carry iTunes' compilation tag. “\(current.displayArtist)” is their album artist.")
    }

    /// Just information: the iPod's firmware rebuilds these songs from their files itself.
    private var syncedBadge: some View {
        Label("Synced by the iPod", systemImage: "arrow.triangle.2.circlepath")
            .font(.theme(.body, weight: .medium)).foregroundStyle(Theme.f2)
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.row, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.glassBorder, lineWidth: 0.5))
            .help("This iPod rebuilds these songs from its Music folder. Deleting them and changing the cover happen in that folder.")
    }

    /// Rare and irreversible actions sit under the three dots next to "Play".
    /// Red shows up only in the expanded menu - a permanently red button
    /// in the header drew the eye too much.
    private var albumMenu: some View {
        Menu {
            Toggle(isOn: Binding(get: { editorShown },
                                 set: { value in withAnimation(Self.editorAnimation) { editorShown = value } })) {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            Button("Add Songs to This Album…", systemImage: "plus", action: chooseSongs)
                .disabled(!model.isWritable)
            if current.isCompilation {
                Button("Take Out of Compilations…", systemImage: "person.2.slash", action: clearCompilation)
            }
            // Deleting has its own section with a header, so it does not lie right under
            // an item used every day - one mouse move too far
            // and the album is gone.
            Section("Remove from the iPod") {
                Button("Delete Album…", systemImage: "trash", role: .destructive, action: deleteAlbum)
                    .disabled(synced)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.theme(.body, weight: .semibold))
                .frame(width: 13)
                .glassChip()
        }
        .chipMenu()
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions for this album")
    }

    private var meta: String {
        var parts: [String] = []
        if let genre = current.genre, !genre.isEmpty { parts.append(genre) }
        if let year = current.year { parts.append(String(year)) }
        parts.append("\(current.trackCount) song\(current.trackCount == 1 ? "" : "s")")
        parts.append(current.duration.minutesLabel)
        return parts.joined(separator: " · ")
    }

    /// Artwork with editing: on hover the "Change Cover…" button, a context
    /// menu, dropping an image file. Preview right away, the file on the iPod
    /// only after "Write to iPod".
    private func coverEditor(size: CGFloat, corner: CGFloat) -> some View {
        CoverEditor(size: size, corner: corner, image: image, choose: chooseCover, drop: { url in setCover(from: url) },
                    locked: synced ? "This iPod takes the cover from the album's folder in its Music folder." : nil)
    }

    private func chooseCover() {
        if let cover = coverFile {
            setCover(from: cover)
            return
        }
        // The iPod gets RGB565 in three sizes anyway, not the source file.
        guard let url = FilePanels.chooseImage(
            message: "Choose a new cover for “\(current.displayTitle)”: JPEG, PNG, HEIC, TIFF or any other image macOS can open. A square image works best.",
            prompt: "Use as Cover") else { return }
        setCover(from: url)
    }

    private func setCover(from url: URL) {
        attempt { try model.setArtwork(for: current, imageFileAt: url) }
    }

    @ViewBuilder private var artwork: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack { Theme.card; Image(systemName: "music.note").font(.symbol(.placeholder, weight: .light)).foregroundStyle(Theme.f3) }
        }
    }

    /// The column header - separate, because it lies once in the list, once in the render column.
    private var columnTitles: some View {
        Group {
            HStack(spacing: TrackColumns.spacing) {
                Text("#").frame(width: TrackColumns.number, alignment: .trailing)
                Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                Text("Plays").frame(width: TrackColumns.plays, alignment: .trailing)
                Text("Time").frame(width: TrackColumns.time, alignment: .trailing)
                Spacer().frame(width: TrackColumns.menu)
            }
            .font(.theme(.caption)).foregroundStyle(Theme.f2)
            .padding(EdgeInsets(top: 0, leading: TrackColumns.inset, bottom: 6, trailing: TrackColumns.inset))
            .overlay(alignment: .bottom) { Theme.sep.frame(height: 0.5) }
            .padding(.horizontal, 24)
        }
    }

    private func trackList(_ rows: [TrackRow]) -> some View {
        // We handle selection ourselves: the native List highlight on macOS
        // floods the whole row edge to edge, and the design has a pill.
        List {
            // The album header is a row of the list, not a panel above it -
            // otherwise only the list would scroll, and the artwork and title would stay
            // in place.
            Group {
                header(rows)
                unplayableNotice(rows)
                columnTitles
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(true)
            .selectionDisabled()

            ForEach(rows) { row in
                TrackRowView(row: row,
                             selected: selection.contains(row.id),
                             playing: playback.currentTrack?.id == row.id,
                             editing: editingField(for: row),
                             restoring: model.changes.fileImports[row.id].flatMap { $0.isReplacement ? nil : $0.source.lastPathComponent },
                             replacing: model.changes.fileImports[row.id].flatMap { $0.isReplacement ? $0.source.lastPathComponent : nil },
                             play: { playback.play(rows, startingAt: row, in: current) },
                             select: {
                                 if NSEvent.modifierFlags.contains(.command) {
                                     if selection.contains(row.id) { selection.remove(row.id) } else { selection.insert(row.id) }
                                 } else {
                                     selection = [row.id]
                                 }
                             },
                             menu: { rowMenu(row, in: rows) },
                             commitTitle: { title in
                                 editing = nil
                                 model.renameTrack(row, in: current, to: title)
                             },
                             commitNumber: { number in
                                 editing = nil
                                 model.setTrackNumber(row, in: current, to: number)
                             },
                             cancelEdit: { editing = nil })
                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu { rowMenu(row, in: rows) }
            }
            .onMove { offsets, destination in
                attempt { try model.moveTracks(in: current, fromOffsets: offsets, toOffset: destination) }
            }
            // Files from Finder dropped between tracks go into this album,
            // at that place - without matching tags in the import dialog.
            .onInsert(of: model.isWritable ? [.fileURL] : []) { index, providers in receive(providers, at: index) }

            ForEach(model.pendingAdditions(for: current)) { addition in
                PendingAdditionRow(addition: addition, remove: { model.removeQueuedAddition(addition.id) })
                    .listRowInsets(EdgeInsets(top: 2, leading: 24, bottom: 2, trailing: 24))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
                    .selectionDisabled()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .focusable()
        .focused($listFocused)
        // The list holds focus only so that Escape and the arrows work
        // right away - without this the system draws a blue ring around it.
        .focusEffectDisabled()
        .onAppear { listFocused = true }
        .onDeleteCommand { for id in selection { if let row = rows.first(where: { $0.id == id }) { delete(row) } } }
        // Return on a single selected row opens title editing.
        .onKeyPress(.return) {
            guard editing == nil, selection.count == 1, let id = selection.first else { return .ignored }
            editing = .title(id)
            return .handled
        }
    }

    /// The album's tracks the iPod will not play - with a conversion offer.
    @ViewBuilder private func unplayableNotice(_ rows: [TrackRow]) -> some View {
        let bad = rows.filter { $0.unplayable }
        if !bad.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.destructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bad.count == rows.count
                         ? "The iPod can't play this album"
                         : "The iPod can't play \(bad.count) of these songs")
                        .font(.theme(.body, weight: .semibold))
                    Text(bad.first?.formatVerdict?.reason ?? "")
                        .font(.theme(.caption)).foregroundStyle(Theme.f2)
                }
                Spacer()
                Button("Convert \(bad.count == 1 ? "It" : "Them")…") { convert(bad) }
                    .font(.theme(.callout, weight: .medium)).buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.destructive.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(EdgeInsets(top: 8, leading: 24, bottom: 10, trailing: 24))
        }
    }

    /// Conversion through the model; the user chooses the place for the originals every time.
    private func convert(_ selection: [TrackRow]) {
        let label = selection.count == 1 ? "“\(selection[0].displayTitle)”" : "\(selection.count) songs in “\(current.displayTitle)”"
        let choice = OriginalsPicker.ask(for: label, fileCount: selection.count, sizeHint: nil)
        let directory: URL?
        switch choice {
        case .keep(let url): directory = url
        case .discard: directory = nil
        case .cancelled: return
        }
        attempt {
            for row in selection { try model.convertTrack(row, in: current, keepOriginalsIn: directory) }
        }
    }

    /// "Add Songs to This Album…": the chosen files go to the end of the album.
    private func chooseSongs() {
        let urls = FilePanels.chooseAudio(
            message: "Choose songs to add to \u{201C}\(current.title)\u{201D}. They go on the iPod when you choose Write to iPod.",
            prompt: "Add to Album")
        guard !urls.isEmpty else { return }
        Task { await add(urls, at: nil) }
    }

    private func receive(_ providers: [NSItemProvider], at index: Int) {
        Task { await add(await NSItemProvider.fileURLs(from: providers), at: index) }
    }

    /// Folders are expanded to audio files the same way as an album import.
    private func add(_ urls: [URL], at index: Int?) async {
        let files = AudioImport.expandingFolders(urls)
        guard !files.isEmpty else { return }
        let refused = await model.addFiles(files, to: current, at: index)
        if !refused.isEmpty { error = refused.map(ErrorPresenter.line).joined(separator: "\n") }
    }

    /// A file for one track, without opening the whole add dialog.
    private enum FileJob {
        /// An entry without a file gets a file.
        case restore
        /// A track with a file gets a new one - the old one disappears after the write.
        case replace
    }

    /// The file goes through the same compatibility verdict as an album import - if
    /// the iPod will not play it, the conversion waits together with the change.
    private func chooseFile(for row: TrackRow, _ job: FileJob) {
        let title = "\u{201C}\(row.displayTitle)\u{201D}"
        let panel = switch job {
        case .restore: (message: "Choose the audio file for \(title).", prompt: "Use This File")
        case .replace: (message: "Choose a new audio file for \(title). "
                            + "The song keeps its title, play count, rating and playlists; only the file changes.",
                        prompt: "Replace")
        }
        guard let url = FilePanels.chooseAudioFile(message: panel.message, prompt: panel.prompt) else { return }
        Task {
            guard let candidate = await model.inspect(url) else {
                error = "\(url.lastPathComponent) isn't an audio file Clickwill can read. Choose an MP3, AAC, Apple Lossless, WAV, AIFF or FLAC file."
                return
            }
            attempt {
                switch job {
                case .restore: try model.importFile(candidate, for: row, in: current)
                case .replace: try model.replaceFile(candidate, for: row, in: current)
                }
            }
        }
    }

    /// Deleting a whole album. The confirmation says plainly what a backup
    /// will not undo, and offers a middle way - copies of the files on the Mac.
    private func deleteAlbum() {
        let choice = DeleteAlbumConfirmation.ask(
            album: current.displayTitle, artist: current.displayArtist,
            trackCount: current.trackCount, fileCount: model.deletableFileCount(of: current))
        let archive: URL?
        switch choice {
        case .cancelled: return
        case .delete: archive = nil
        case .deleteKeepingCopies(let url): archive = url
        }
        attempt {
            try model.deleteAlbum(current, keepCopiesIn: archive)
            onDeleted()
        }
    }

    private func delete(_ row: TrackRow) {
        attempt {
            try model.deleteTrack(row, in: current)
            selection.remove(row.id)
        }
    }

    @ViewBuilder private func rowMenu(_ row: TrackRow, in rows: [TrackRow]) -> some View {
        Button("Play") { playback.play(rows, startingAt: row, in: current) }
        Divider()
        Button("Edit Title") { selection = [row.id]; editing = .title(row.id) }
        Button("Edit Track Number") { selection = [row.id]; editing = .number(row.id) }
        Button("Renumber Tracks 1…\(rows.count)") { attempt { try model.renumberTracks(in: current) } }
        if row.fileMissing {
            Divider()
            if model.changes.fileImports[row.id] == nil {
                Button("Give It a File…") { chooseFile(for: row, .restore) }
            } else {
                Button("Leave It Without a File") { model.cancelFileImport(row.id) }
            }
        } else {
            Divider()
            if row.unplayable {
                Button("Convert so the iPod Can Play It…") { convert([row]) }
            }
            // A replacement: a bad rip, another version, better quality. The record stays -
            // the title, plays, rating, playlists - only the file changes.
            if model.changes.fileImports[row.id]?.isReplacement == true {
                Button("Keep the Current File") { model.cancelFileImport(row.id) }
            } else {
                Button("Replace Audio File…") { chooseFile(for: row, .replace) }
            }
        }
        Divider()
        Button("Delete from iPod", role: .destructive) { delete(row) }
            .disabled(model.isSyncedOnDevice(row))
    }

    private func clearCompilation() {
        guard CompilationConfirmation.askToTakeOut(current) else { return }
        model.setCompilation(current, false)
    }

    /// The screen's only error path: a model command, and its refusal in an alert.
    private func attempt(_ edit: () throws -> Void) {
        do { try edit() } catch { self.error = ErrorPresenter.message(for: error) }
    }

    private func editingField(for row: TrackRow) -> TrackRowField? {
        switch editing {
        case .title(row.id): return .title
        case .number(row.id): return .number
        default: return nil
        }
    }

    /// An inspector field goes to all tracks of the album; changing the title or
    /// the artist gives a card with a new identifier - we adopt it.
    private func commitAlbumField(_ field: AlbumField, _ value: String) {
        attempt { try model.setAlbumField(current, field, to: value) }
    }

    private var inspector: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    coverEditor(size: 132, corner: 8)
                    Spacer()
                }
            }
            splitNotice
            syncedNotice
            Section("Album") {
                editableField(.title, current.title)
                editableField(.albumArtist, current.artist, placeholder: "Unknown Artist")
                editableField(.year, current.year.map(String.init) ?? "", placeholder: "None")
                editableField(.genre, current.genre ?? "", placeholder: "None")
            }
            Section {
                LabeledContent("Songs", value: "\(current.trackCount)")
                LabeledContent("Position on iPod", value: "\((model.coverFlowAlbums.firstIndex { $0.id == current.id } ?? 0) + 1) of \(model.coverFlowAlbums.count)")
                LabeledContent("Albums menu position", value: "\((model.index(of: current) ?? 0) + 1) of \(model.albums.count)")
            } header: {
                Text("On the iPod")
            } footer: {
                // The color explicitly: the window imposes Theme.fg on all texts, footers included.
                Text("These fields apply to every song in the album. Drag songs to reorder them. Nothing reaches the iPod until you choose Write to iPod.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// An album split into several cards (a different album artist, the compilation flag,
    /// a different mhia record): an offer to merge them into one.
    @ViewBuilder private var splitNotice: some View {
        let siblings = model.splitSiblings(of: current)
        if !siblings.isEmpty {
            Section {
                Label("This album is split", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("“\(current.displayTitle)” appears \(siblings.count + 1) times on the iPod because its songs aren't all tagged the same way.")
                    .foregroundStyle(.secondary)
                ForEach(siblings) { other in
                    if other.trackCount >= current.trackCount {
                        Button(current.trackCount == 1
                               ? "Merge This Song into the \(other.trackCount)-Song Album"
                               : "Merge These \(current.trackCount) Songs into the \(other.trackCount)-Song Album") {
                            model.mergeAlbum(current, into: other)
                        }
                    } else {
                        Button("Merge the \(other.trackCount)-Song Copy into This Album") {
                            model.mergeAlbum(other, into: current)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var syncedNotice: some View {
        if synced {
            Section {
                Label("Synced by the iPod", systemImage: "arrow.triangle.2.circlepath")
                Text("This iPod rebuilds these songs from the album's folder in its Music folder every time it starts or leaves a Mac. Changes to titles and details last until the file changes. To delete a song or change the cover, change the folder on the iPod.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A field committed with Return or by losing focus; Escape reverts.
    private func editableField(_ field: AlbumField, _ value: String, placeholder: String = "") -> some View {
        InspectorTextField(label: field.rawValue, value: value, placeholder: placeholder) { commitAlbumField(field, $0) }
    }
}
