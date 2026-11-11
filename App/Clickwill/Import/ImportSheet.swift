import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClickwillModel
import ITDBKit

/// Importing tracks: choosing files, reviewing what came out of the tags, corrections
/// before the write. Nothing reaches the iPod from this dialog - confirming adds
/// an item to the list of pending changes, like any other edit.
struct ImportSheet: View {
    /// Files chosen in a panel that opened **before** the sheet.
    /// A modal panel started from inside a presented sheet does not show
    /// at all - both fight over the same window.
    let initialURLs: [URL]

    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The files, their albums, duplicates and decisions - the session computes what goes into the queue.
    /// It gets the index of what already exists when the sheet opens (`.task`).
    @State private var session = ImportSession(existing: SongIndex())
    /// Previewing a file before adding - one question: is it really this file.
    @State private var preview = PreviewPlayer()
    @State private var reading = false
    /// What could not be queued after "Add" - shown before the sheet
    /// closes, not lost together with it.
    @State private var refused: ImportSession.Commit?
    /// "Add" was clicked with files the iPod's firmware may skip - the sheet asks first.
    @State private var confirmingSkippable = false

    var body: some View {
        // Standard parts only, per the Human Interface Guidelines for macOS: a sheet with its
        // buttons in their system places, a pop-up button with its explanation under it, and
        // a list of songs grouped by album. Controls stay at the top, away from the window's
        // bottom edge (Layout).
        NavigationStack {
            Group {
                if reading {
                    progress
                } else if session.candidates.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("Add Songs")
            .onChange(of: session.candidates.map(\.id)) { session.refreshMatches(in: model) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        if session.mayBeSkippedCount(in: model) > 0 { confirmingSkippable = true } else { addToLibrary() }
                    }
                    .disabled((session.toAdd(in: model).isEmpty && session.replaceCount == 0) || reading)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 440, idealHeight: 600)
        // More files from Finder straight onto the open dialog, like "Choose More Files…".
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty, !reading else { return false }
            Task { await read(files) }
            return true
        }
        .task {
            guard session.candidates.isEmpty else { return }
            session = ImportSession(existing: model.songIndex(), capabilities: model.capabilities)
            if !initialURLs.isEmpty { await read(initialURLs) }
        }
        // The sheet is modal: closing it without stopping the preview
        // would leave a file playing with no control to stop it.
        .onDisappear { preview.stop() }
        .alert("Preview", isPresented: Binding(get: { preview.errorMessage != nil },
                                               set: { if !$0 { preview.errorMessage = nil } })) {
            Button("OK", role: .cancel) { preview.errorMessage = nil }
        } message: {
            Text(preview.errorMessage ?? "")
        }
        // The rest is already on the change list; the sheet closes after being read.
        .alert(refusalTitle, isPresented: Binding(get: { refused != nil }, set: { _ in })) {
            Button("OK") { refused = nil; dismiss() }
        } message: {
            Text(refusalMessage)
        }
        .alert(skippableTitle, isPresented: $confirmingSkippable) {
            Button("Add Anyway") { addToLibrary() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(skippableMessage)
        }
    }

    // MARK: - Parts

    private var progress: some View {
        ProgressView("Reading tags…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("Choose Audio Files or a Folder", systemImage: "music.note.list")
        } description: {
            Text("Drag them here from Finder, or choose them. A folder is read as an album: tracks keep the order of their numbers, or of their file names when the numbers are missing.")
        } actions: {
            Button("Choose Files…") { choose() }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            List {
                if !session.problems.isEmpty { problemSection }
                ForEach(session.albums, id: \.id) { group in
                    Section {
                        if let match = session.matches[group.id] { matchRow(group, match) }
                        ForEach(group.songs) { candidate in row(candidate) }
                    } header: {
                        albumHeader(group)
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
        }
    }

    /// What applies to the whole sheet, above the songs it applies to.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Sets every song. When songs differ, it shows the mixed state (HIG, Pop-up buttons).
                Picker("Format", selection: Binding<ImportFormat?>(
                    get: { session.commonFormat },
                    set: { if let format = $0 { session.setFormat(format) } }
                )) {
                    if session.commonFormat == nil {
                        Text("Mixed").tag(ImportFormat?.none)
                        Divider()
                    }
                    ForEach(ImportFormat.allCases) { Text($0.label).tag(ImportFormat?.some($0)) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Spacer(minLength: 12)
                Text(summary).foregroundStyle(.secondary).monospacedDigit()
                Button("Choose More Files…") { choose() }
                    .disabled(reading)
            }
            Text(session.commonFormat?.detail ?? "Songs have different formats. Choosing one here sets it for every song.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            notes
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// The section header of an album: artwork, the album name and album artist (correctable
    /// in place), and what is being added.
    private func albumHeader(_ group: ImportAlbum) -> some View {
        HStack(alignment: .center, spacing: 12) {
            cover(for: group)
            VStack(alignment: .leading, spacing: 4) {
                ImportField(text: albumBinding(group.id), placeholder: "Add album name", font: .headline)
                HStack(spacing: 8) {
                    ImportField(text: albumArtistBinding(group.id), placeholder: "Add album artist", font: .subheadline)
                        .foregroundStyle(.secondary)
                    // A CD carries the artist in no file - without
                    // this it had to be typed in every row separately.
                    if let artist = session.albumArtist(of: group.id), session.songsDiffer(in: group.id, from: artist) {
                        Button("Apply to All \(group.songs.count) Songs") { session.editGroup(group.id) { $0.artist = artist } }
                            .controlSize(.small)
                            .fixedSize()
                            .help("Sets \u{201C}\(artist)\u{201D} as the artist of every song in this album.")
                    }
                }
                Text(albumDetail(group))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 8)
        }
        .textCase(nil)
        .padding(.vertical, 6)
    }

    private func albumDetail(_ group: ImportAlbum) -> String {
        let songs = "\(group.songs.count) \(group.songs.count == 1 ? "song" : "songs")"
        let isNew = isNewAlbum(group.songs.first?.draft.albumKey)
            && (session.matches[group.id] == nil || session.choice(for: group.id) == .separate)
        return isNew ? "New album · \(songs)" : songs
    }

    private func row(_ candidate: AudioImport.Candidate) -> some View {
        let draft = candidate.draft
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                PreviewButton(id: candidate.id, url: candidate.url, preview: preview)
                ImportField(text: numberBinding(candidate.id), placeholder: "–", font: .body.monospacedDigit(),
                            width: 28, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    ImportField(text: titleBinding(candidate.id), placeholder: "Add title", font: .body)
                    // When replacing files the iPod keeps its own data, so an empty
                    // artist field would only invite typing in vain.
                    if session.replacedRow(candidate) == nil || !artistBinding(candidate.id).wrappedValue.isEmpty {
                        ImportField(text: artistBinding(candidate.id), placeholder: "Add artist", font: .subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let replaced = session.replacedRow(candidate) {
                        Label("Replaces \u{201C}\(replaced.displayTitle)\u{201D} on the iPod", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if session.showsDuplicates(candidate), let place = session.place(of: candidate) {
                        duplicateControl(candidate, place: place).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(session.isLeftOut(candidate) ? 0.5 : 1)
                formatColumn(candidate)
                    .frame(width: 220, alignment: .leading)
                Text(ByteCountFormatter.string(fromByteCount: Int64(draft.sizeBytes), countStyle: .file))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
                Button {
                    if preview.isLoaded(candidate.id) { preview.stop() }
                    session.remove(candidate.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("Leave this file out")
                .accessibilityLabel("Leave \(draft.title) out")
            }
            if preview.isLoaded(candidate.id) {
                PreviewScrubber(id: candidate.id, preview: preview)
                    .padding(.leading, 32).padding(.trailing, 4)
            }
        }
        .padding(.vertical, 2)
    }

    /// The file's format, and what happens to it on the way to the iPod.
    private func formatColumn(_ candidate: AudioImport.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.formatLabel).foregroundStyle(.secondary)
            formatPicker(candidate)
            if let reason = unchangedReason(candidate) {
                Text("Stays as it is").foregroundStyle(.secondary).help(reason)
            }
            if candidate.verdict.isSupported == false, let target = conversionTarget(candidate) {
                Label(target, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .help("Converted to \(target)")
            }
            if candidate.mayBeSkipped { warning("Your iPod may skip it") }
        }
        .font(.subheadline)
        .lineLimit(1)
    }

    /// One song's format. The Format pop-up at the top shows "Mixed" once songs differ.
    private func formatPicker(_ candidate: AudioImport.Candidate) -> some View {
        Picker("Format of \(candidate.draft.title)", selection: Binding(
            get: { session.format(of: candidate) },
            set: { session.setFormat($0, for: candidate.id) }
        )) {
            ForEach(ImportFormat.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help("The format of this song only.")
    }

    /// Why a chosen format leaves this file as it is. Without it, choosing Apple Lossless for an
    /// AAC file would look like a choice that did nothing. Automatic and Keep Original leave
    /// files as they are by definition, so they need no explanation.
    private func unchangedReason(_ candidate: AudioImport.Candidate) -> String? {
        guard candidate.verdict.isSupported else { return nil }
        switch session.format(of: candidate) {
        case .automatic, .original:
            return nil
        case .appleLossless:
            return candidate.draft.kind.isLossless
                ? "It's already Apple Lossless that your iPod can play."
                : "It's a compressed file, so Apple Lossless wouldn't improve the sound. It would only take more space."
        case .aac256, .aac128:
            return "Its bit rate is already this low or lower, so converting it would only lose quality."
        }
    }

    /// A warning: the system's multicolor triangle next to plain text.
    private func warning(_ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
        }
    }

    /// A track that already exists is skipped by default - the same file a second time
    /// takes space and duplicates the song in the iPod menu. One click
    /// adds it anyway, e.g. when it is a different version with the same name.
    private func duplicateControl(_ candidate: AudioImport.Candidate, place: SongIndex.Place) -> some View {
        let forced = session.isAddedAnyway(candidate)
        return HStack(spacing: 8) {
            warning(place == .onIPod ? "Already on the iPod" : "Already in the list of changes")
                .font(.caption)
                .fixedSize()
            Button(forced ? "Skip" : "Add Anyway") {
                session.toggleAddAnyway(candidate)
            }
            .controlSize(.mini)
            .fixedSize()
        }
        .help(place == .onIPod
              ? "A song with this title, artist, album and length is already on the iPod. It is skipped unless you add it anyway."
              : "This song is already waiting in the list of changes. It is skipped unless you add it anyway.")
    }

    private func addToLibrary() {
        let commit = session.commit(to: model)
        if commit.refused.isEmpty { dismiss() } else { refused = commit }
    }

    private var skippableTitle: String {
        let count = session.mayBeSkippedCount(in: model)
        return count == 1 ? "Add 1 Song Your iPod May Skip?" : "Add \(count) Songs Your iPod May Skip?"
    }

    private var skippableMessage: String {
        if session.mayBeSkippedCount(in: model) == 1 {
            return "The iPod's original firmware may not support this format and will skip this song when it comes up. It still shows in your library. If you want it to play, choose Automatic to convert it."
        }
        return "The iPod's original firmware may not support this format and will skip these songs when they come up. They still show in your library. If you want them to play, choose Automatic to convert them."
    }

    private var refusalTitle: String {
        let count = refused?.refused.count ?? 0
        return count == 1 ? "1 Song Wasn't Added" : "\(count) Songs Weren't Added"
    }

    /// "The rest" only when something from the same "Add" went onto the list.
    private var refusalMessage: String {
        guard let refused else { return "" }
        let list = refused.refused.map(ErrorPresenter.line).joined(separator: "\n")
        return refused.queued > 0 ? list + "\n\nEverything else is in the list of changes." : list
    }

    private var confirmTitle: String {
        let add = session.toAdd(in: model).count, replace = session.replaceCount, skippedCount = session.skippedCount
        switch (add, replace) {
        case (0, let r) where r > 0: return "Replace \(r) \(r == 1 ? "File" : "Files")"
        case (let a, let r) where r > 0: return "Add \(a), Replace \(r)"
        default: return skippedCount > 0 && add > 0 ? "Add \(add) to Library" : "Add to Library"
        }
    }

    /// A warning above the songs: this album already exists, and a choice of what to do with it.
    private func matchRow(_ group: ImportAlbum, _ match: AlbumMatch) -> some View {
        let total = max(group.songs.count, match.album.trackCount)
        let binding = Binding(get: { session.choice(for: group.id) }, set: { session.choose($0, for: group.id) })
        return VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("This looks like \u{201C}\(match.album.displayTitle)\u{201D} by \(match.album.displayArtist), already on your iPod. \(match.pairs.count) of \(total) songs match.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
            }
            Picker("What to do with this album", selection: binding) {
                Text("Replace Files").tag(ImportSession.AlbumChoice.replace)
                Text("Skip").tag(ImportSession.AlbumChoice.skip)
                Text("Add as a Separate Album").tag(ImportSession.AlbumChoice.separate)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Group {
                switch binding.wrappedValue {
                case .replace:
                    Text("The songs on the iPod keep their titles, play counts, ratings, cover and order. Only the files change, and the old files are removed after a successful write.")
                case .skip:
                    Text("Nothing from this folder is added. The album on the iPod stays as it is.")
                case .separate:
                    Text("A second copy of the album is added next to the one on the iPod.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            if binding.wrappedValue == .replace, !match.isComplete {
                if !match.missingRows.isEmpty {
                    Text("Not in these files, so they stay as they are: \(match.missingRows.map(\.displayTitle).joined(separator: ", ")).")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let extra = group.songs.filter { match.extraCandidates.contains($0.id) }.map(\.draft.title)
                if !extra.isEmpty {
                    Text("Added to the album on the iPod: \(extra.joined(separator: ", ")).")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var problemSection: some View {
        Section {
            ForEach(Array(session.problems.enumerated()), id: \.offset) { _, problem in
                warning(ErrorPresenter.line(problem))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Notes before adding, only when there is something to say: skipped duplicates, albums
    /// without artwork, conversions, and an iPod whose model was not recognized.
    @ViewBuilder private var notes: some View {
        let skippedCount = session.skippedCount, replaceCount = session.replaceCount
        let coverless = session.coverless(in: model), converting = session.converting
        Group {
            if skippedCount > 0 {
                Label(skippedCount == 1
                      ? "1 song is already there and will be skipped."
                      : "\(skippedCount) songs are already there and will be skipped.",
                      systemImage: "arrow.uturn.right")
            }
            if replaceCount > 0 {
                Label(replaceCount == 1
                      ? "1 file replaces a song already on the iPod."
                      : "\(replaceCount) files replace songs already on the iPod.",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            if coverless > 0 {
                Label(coverless == 1
                      ? "1 new album has no cover. Click its thumbnail to choose one."
                      : "\(coverless) new albums have no cover. Click a thumbnail to choose one.",
                      systemImage: "photo.badge.plus")
            }
            if converting > 0 {
                Label("\(converting) \(converting == 1 ? "file needs" : "files need") converting first. Your own copies stay where they are.",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            // The limits by which we judge files depend on the model.
            if model.capabilities.isAssumed {
                Label("I couldn't recognize this iPod's exact model, so I checked these files against \(model.capabilities.name).",
                      systemImage: "questionmark.circle")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: - Data

    private var summary: String {
        let songs = session.candidates.count, albums = session.albums.count
        let size = ByteCountFormatter.string(fromByteCount: session.totalBytes, countStyle: .file)
        return "\(songs) \(songs == 1 ? "song" : "songs") · \(albums) \(albums == 1 ? "album" : "albums") · \(size)"
    }

    private func conversionTarget(_ candidate: AudioImport.Candidate) -> String? {
        if case .convertible(_, let target) = candidate.verdict { return target.label }
        return nil
    }

    private func isNewAlbum(_ key: AlbumKey?) -> Bool { session.isNewAlbum(key, in: model) }

    /// The artwork the new album will get.
    ///
    /// Until now it was only a preview of what was found in the tags or
    /// in the folder. An album with neither had no way
    /// to get it - it went to the iPod without artwork, and that was only visible
    /// there. Now the thumbnail is a button.
    @ViewBuilder private func cover(for group: ImportAlbum) -> some View {
        let origin = group.songs.first?.coverOrigin ?? .none
        let source = group.songs.compactMap(\.coverSource).first
        let image = source.flatMap { try? TrackAdditionRunner.coverImage(from: $0).image }
        let isNew = isNewAlbum(group.songs.first?.draft.albumKey)

        Button { chooseCover(for: group) } label: {
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.fill.tertiary)
                    Image(systemName: "photo.badge.plus").font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isNew)
        .opacity(isNew ? 1 : 0.5)
        .help(coverHelp(origin: origin, source: source, isNew: isNew))
        .contextMenu {
            if isNew {
                Button("Choose Cover…") { chooseCover(for: group) }
                if origin == .chosen {
                    Button("Use the Cover Found in the Files") { session.setCover(nil, for: group.id) }
                }
            }
        }
    }

    private func coverHelp(origin: AudioImport.Candidate.CoverOrigin,
                           source: AudioImport.CoverSource?, isNew: Bool) -> String {
        guard isNew else {
            return "This album is already on the iPod and keeps its cover. Change it from the album view."
        }
        switch origin {
        case .chosen: return "Cover \(source?.label ?? ""), chosen by you. Click to pick another."
        case .tags: return "Cover \(source?.label ?? ""). Click to use a different image."
        case .folder: return "Cover \(source?.label ?? ""). Click to use a different image."
        case .none: return "No cover found in the files or the folder. Click to choose an image."
        }
    }

    /// An image chosen by hand. We check it right away - a file that cannot be
    /// read should speak up here, not only when writing to the iPod.
    private func chooseCover(for group: ImportAlbum) {
        guard let url = FilePanels.chooseImage(message: "Choose the cover for this album.", prompt: "Use This Image") else { return }
        do {
            _ = try TrackAdditionRunner.coverImage(from: .file(url))
            session.setCover(url, for: group.id)
        } catch {
            session.note(.unreadableCover(url))
        }
    }

    // MARK: - Editing before the write

    /// The fields are bound directly to the session: a correction applies to what goes into
    /// the database, not to the file on disk - its tags are not touched.
    private func field(_ id: UUID, _ get: @escaping (TrackDraft) -> String,
                       _ set: @escaping (inout TrackDraft, String) -> Void) -> Binding<String> {
        Binding(get: { session.draft(of: id).map(get) ?? "" },
                set: { value in session.edit(id) { set(&$0, value) } })
    }

    private func titleBinding(_ id: UUID) -> Binding<String> {
        field(id, { $0.title }, { $0.title = $1 })
    }

    private func artistBinding(_ id: UUID) -> Binding<String> {
        field(id, { $0.artist ?? "" }, { $0.artist = $1.isEmpty ? nil : $1 })
    }

    private func numberBinding(_ id: UUID) -> Binding<String> {
        field(id, { $0.trackNumber > 0 ? String($0.trackNumber) : "" },
              { $0.trackNumber = UInt32($1.filter(\.isNumber)) ?? 0 })
    }

    /// The album name and album artist apply to the whole group - otherwise a correction
    /// in one row would split the album in two.
    private func groupField(_ group: UUID, _ get: @escaping (TrackDraft) -> String,
                            _ set: @escaping (inout TrackDraft, String) -> Void) -> Binding<String> {
        Binding(get: { session.groupDraft(group).map(get) ?? "" },
                set: { value in session.editGroup(group) { set(&$0, value) } })
    }

    private func albumBinding(_ group: UUID) -> Binding<String> {
        groupField(group, { $0.album ?? "" }, { $0.album = $1.isEmpty ? nil : $1 })
    }

    private func albumArtistBinding(_ group: UUID) -> Binding<String> {
        groupField(group, { $0.albumArtist ?? "" }, { $0.albumArtist = $1.isEmpty ? nil : $1 })
    }

    // MARK: - Choosing files

    private func choose() {
        let urls = Self.chooseFiles()
        guard !urls.isEmpty else { return }
        Task { await read(urls) }
    }

    /// The file choose panel. Static, because we also open it from the sidebar,
    /// before the sheet even exists.
    @MainActor
    static func chooseFiles() -> [URL] {
        FilePanels.chooseAudio(message: "Choose audio files, or a folder holding an album.", prompt: "Choose")
    }

    private func read(_ urls: [URL]) async {
        reading = true
        let found = await AudioImport.candidates(at: urls, on: model.capabilities)
        session.add(found.ready, problems: found.problems)
        session.refreshMatches(in: model)
        reading = false
    }
}
