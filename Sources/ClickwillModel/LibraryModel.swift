import Foundation
import Observation
import CoreGraphics
import ITDBKit

/// The library state in the app.
///
/// Every edit is applied right away to `library` in memory with core functions -
/// the same ones the CLI has. What waits for the write is kept by `changes`: the log for
/// the user and the device tasks (files, artwork, conversions).
/// Only `apply()` touches the device, through the same write path with preflight.
@MainActor
@Observable
public final class LibraryModel {

    public enum State: Equatable, Sendable {
        case empty
        case loading
        case loaded
        case failed(Failure)
    }

    /// Why there is no library, although there was or was supposed to be one.
    public enum Failure: Equatable, Sendable, CustomStringConvertible {
        /// Reading the library failed.
        case loading(any Error)
        /// The iPod disappeared while there were unsaved changes in the queue - they are lost.
        case disconnected(unsavedChanges: Int)

        /// Equal by accident: the state says loading failed; what exactly
        /// is carried by the error (`description`), not by equality.
        public static func == (lhs: Failure, rhs: Failure) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading): return true
            case (.disconnected(let a), .disconnected(let b)): return a == b
            default: return false
            }
        }

        /// Technical description - for the diagnostic report.
        public var description: String {
            switch self {
            case .loading(let error): return String(describing: error)
            case .disconnected(let unsaved): return "iPod disconnected, \(unsaved) unsaved changes discarded"
            }
        }
    }

    public private(set) var state: State = .empty
    /// The loaded library and everything that follows from its source (`LibrarySession`).
    /// `nil` before the first load and after the iPod is disconnected.
    public private(set) var session: LibrarySession?
    /// Grows with every load and disconnect; a result of background work (the format
    /// scan) computed for the old library must not reach the new one.
    public internal(set) var generation = 0
    public private(set) var preflightState: WritePreflight?

    public var source: LibrarySource? { session?.source }
    public var paths: IPodPaths? { session?.paths }
    /// The library with edits applied; `nil` without a loaded source.
    public var library: ITLibrary? { session?.library }
    public var artwork: ArtworkLibrary? { session?.artwork }
    var sourceDigest: String? { session?.sourceDigest }
    var missingFileIDs: Set<UInt32> { session?.missingFileIDs ?? [] }
    /// Whether file presence can be checked - a snapshot has no Music folder.
    public var canCheckFiles: Bool { session?.canCheckFiles ?? false }
    /// Format limits of the connected model; without a source, the Classic profile.
    public var capabilities: IPodCapabilities { session?.capabilities ?? .classic }
    /// Album cards: the album table and the Cover Flow strip (`AlbumCatalog`).
    public private(set) var catalog = AlbumCatalog.empty
    /// The order from the album table - it governs the Albums menu and the track order.
    public var albums: [AlbumCard] { catalog.albums }
    /// The order in which Cover Flow shows covers on the iPod.
    public var coverFlowAlbums: [AlbumCard] { catalog.coverFlow }
    /// Everything waiting for the write: the log and the tasks for `apply()`.
    /// New albums from the add queue are recomputed on every queue change.
    public internal(set) var changes = ChangeSet() {
        didSet {
            if changes.additions.map(\.id) != oldValue.additions.map(\.id) { refreshPendingAlbums() }
        }
    }
    /// File format compatibility verdicts - filled in by `scanFormats()`.
    public private(set) var formats = FormatReport()
    /// The format compatibility verdict per track.
    public internal(set) var formatVerdicts: [UInt32: AudioCompatibility.Verdict] {
        get { formats.verdicts }
        set { formats.verdicts = newValue }
    }
    /// Format description per track, for the badge in the interface.
    public internal(set) var formatLabels: [UInt32: String] {
        get { formats.labels }
        set { formats.labels = newValue }
    }
    /// Whether the format scan has already gone through the whole library.
    public var formatScanComplete: Bool { formats.isComplete }

    /// New albums from the add queue, and Cover Flow together with them - computed by
    /// `refreshPendingAlbums()`. `coverFlowAlbums` stays what is on the iPod.
    public internal(set) var pendingAlbums: [PendingAlbum] = []
    public internal(set) var coverFlowDisplay: [AlbumCard] = []
    /// The Albums menu as the iPod shows it (`AlbumsMenu`), with the new
    /// albums from the queue. `albums` stays the album table from the database.
    public internal(set) var albumsDisplay: [AlbumCard] = []

    /// Artwork in memory: decoded at the view's request, change previews.
    public let covers = CoverImages()
    /// How long we keep backups. The app layer sets this
    /// from the user's preferences; the core only carries it out.
    public var backupRetention: SnapshotRetention = .standard
    /// Backups, the order intent and the Music check for the write.
    public let environment: LibraryEnvironment
    /// Connected iPods and the memory of the one last loaded.
    public let connections: DeviceConnections
    /// Demo mode - fixed from the moment the model is created.
    public let demo: DemoMode
    /// Experimental iPods and Developer Mode: the `WritePolicy` a loaded device gets.
    public let permissions: ExperimentalPermissions

    public init(environment: LibraryEnvironment = .standard, connections: DeviceConnections? = nil, demo: DemoMode = .off,
                permissions: ExperimentalPermissions? = nil) {
        self.environment = environment
        self.connections = connections ?? DeviceConnections()
        self.demo = demo
        self.permissions = permissions ?? ExperimentalPermissions()
        if !demo.choices.isEmpty { self.connections.demoChoices = demo.choices }
    }

    // MARK: - Loading

    /// Whether the interface should allow editing. A backup from disk shown in demo
    /// mode as an iPod (`DemoMode.deviceDetail`) does too - the write will refuse anyway.
    public var isWritable: Bool { source?.isWritable == true || demo.presentsAsDevice(source) }
    /// Writing to the iPod blocked by demo mode (`DemoMode.blocksWrites`).
    public var writesBlocked: Bool { demo.blocksWrites }
    /// Description of the pretend iPod in the sidebar (`DemoMode.deviceDetail`).
    public var demoDeviceDetail: String? { demo.deviceDetail }
    /// Why it cannot be written.
    public enum WriteUnavailable: Equatable {
        /// The device's real reason (e.g. a read-only nano), when we know it.
        case device(ReadOnlyReason?)
        /// A library from a backup on disk.
        case snapshot
    }

    /// `nil` when writing is possible or there is nothing to write (no library).
    public var writeUnavailable: WriteUnavailable? {
        guard !isWritable else { return nil }
        if let device { return .device(device.readOnlyReason) }
        if case .snapshot = source { return .snapshot }
        return nil
    }
    /// Anything waiting for the write - a log entry or a device task.
    public var hasPendingChanges: Bool { !changes.isEmpty }
    public var trackCount: Int { library?.tracks.count ?? 0 }
    public var artistCount: Int {
        guard let library else { return 0 }
        return Set(library.tracks.compactMap { $0.artist }).count
    }

    public var device: IPodDevice? { session?.device }
    /// Whether the loaded iPod has Cover Flow (`IPodCatalog.Generation.hasCoverFlow`).
    /// When the generation is unknown (a backup from disk, an iPod that says too little
    /// about itself) - yes, as before model recognition.
    public var hasCoverFlow: Bool {
        (device?.catalogEntry?.generation ?? currentChoice?.generation)?.hasCoverFlow ?? true
    }

    /// The Albums menu letter for a card from `albumsDisplay`.
    public func menuLetter(of album: AlbumCard) -> String { AlbumsMenu.letter(of: album) }

    /// Connected iPods to choose from on the device card (`DeviceConnections`).
    public var connectedChoices: [IPodChoice] { connections.choices }
    /// iPods for the chooser in demo mode (`DemoMode.choices`).
    public var demoChoices: [IPodChoice] { connections.demoChoices }

    /// Albums (as in Albums) in which at least one track has an image in `ArtworkDB`.
    /// Not the number of Cover Flow cards - there is a card for an album without artwork too.
    public var albumsWithCover: Int {
        guard let library else { return 0 }
        let byTrack = artwork?.indexedByTrack() ?? [:]
        return albums.filter { card in
            card.trackIndices.contains { library.tracks.indices.contains($0) && byTrack[library.tracks[$0].persistentID] != nil }
        }.count
    }

    /// The name given to the iPod ("Anna's iPod"), and without it the volume name.
    public var deviceName: String? {
        guard let device else { return nil }
        return IPodChoice.displayName(library?.deviceName, volume: device.volume.name)
    }

    /// The list item corresponding to the loaded library.
    public var currentChoice: IPodChoice? { connections.choice(for: source, name: library?.deviceName) }

    /// `force`: after opening the chooser - a write may have changed the used space.
    public func refreshConnectedChoices(force: Bool = false) {
        connections.refresh(force: force, loaded: source, loadedName: library?.deviceName, policy: permissions.policy(for:))
    }

    public func load(_ source: LibrarySource) async {
        let source = withWritePolicy(source)
        state = .loading
        do {
            var session = try LibrarySession.open(source, files: environment.files)
            // A backup shown as an iPod pretends to be a recognized iPod classic.
            if demo.presentsAsDevice(source) { session.capabilities.isAssumed = false }

            // The new state comes in whole only after a successful read - after an error
            // the old library must not be tied to a new write target.
            generation += 1
            let sameSource = self.source == source
            self.session = session
            // With several iPods connected, the next launch will start from this one.
            if let device = session.device { connections.remember(device) }
            changes = ChangeSet()
            formats = FormatReport()
            let loadGeneration = generation
            await covers.reload(paths: session.paths, artwork: session.artwork, keepRequested: sameSource)
            // While waiting, the iPod may have disappeared (a USB reset in the dock) and
            // `deviceDisconnected()` has already cleared the model. Without this check
            // we ended up as .loaded without a source and without a library - an empty screen
            // that never looked for an iPod again.
            guard generation == loadGeneration else { return }
            rebuildCards()
            refreshPreflight()
            state = .loaded
            startFormatScan()
        } catch {
            state = .failed(.loading(error))
        }
    }

    /// Preflight as observable state - to refresh when the window becomes active,
    /// because Music may be closed outside the app.
    public func refreshPreflight() {
        preflightState = device?.preflightForWriting(isMusicRunning: environment.isMusicRunning)
    }

    /// Reloading from the same source - discards the changes.
    public func discardChanges() async {
        guard let source else { return }
        await load(source)
    }

    // MARK: - File formats

    /// A scan after every successful load and after a write that replaced files.
    /// It runs in the background; tests can wait for it to finish.
    @ObservationIgnored private(set) var formatScan: Task<Void, Never>?
    /// Tracks the current scan checks next.
    @ObservationIgnored private var scanQueue = FormatScanQueue([])
    /// The current scan's number: a new scan (e.g. after a write) stops the previous one.
    @ObservationIgnored private var scanNumber = 0
    /// Tracks of the album on screen - also for a scan that starts later (after a write).
    @ObservationIgnored private var scanPriority: [UInt32] = []

    private func startFormatScan() {
        formatScan = Task { await scanFormats() }
    }

    /// Examines the files of the connected iPod (`FormatScanner`) and adds verdicts in batches,
    /// so the view refreshes along the way. A new load or a new scan stops
    /// the previous one - both read from one queue, so only one ever runs.
    private func scanFormats() async {
        guard let session, session.canCheckFiles else { return }
        let started = generation
        scanNumber += 1
        let number = scanNumber
        formats.isComplete = false
        scanQueue = FormatScanQueue(session.library.tracks)
        scanQueue.prioritize(scanPriority)
        let scanner = FormatScanner(paths: session.paths, capabilities: session.capabilities, files: session.files)
        let isCurrent = { self.generation == started && self.scanNumber == number }
        let finished = await scanner.scan(next: { scanQueue.next() }, isCurrent: isCurrent) { batch in
            formats.merge(batch)
            rebuildCards()
        }
        if finished { formats.isComplete = true }
    }

    /// An album is on screen: the scan checks its files next,
    /// so the format warning appears after a few seconds, and not
    /// only when the scan reaches it in library order.
    public func prioritizeFormatCheck(of album: AlbumCard) {
        scanPriority = tracks(of: album).map(\.id)
        scanQueue.prioritize(scanPriority)
    }

    /// The library after an edit command (`edit`) - or the starting state set
    /// by a test. The cards are recomputed only in `rebuildCards()`.
    /// Without a loaded source there is nothing to replace.
    func replaceLibrary(_ library: ITLibrary) { session?.library = library }

    /// Artwork after an edit or after a write that changed `ArtworkDB`.
    func replaceArtwork(_ artwork: ArtworkLibrary?) { session?.artwork = artwork }

    // MARK: - Cards

    func rebuildCards() {
        catalog = library.map { AlbumCatalog(library: $0, artwork: artwork, missingFiles: missingFileIDs) } ?? .empty
        refreshPendingAlbums()
    }

    // MARK: - Artwork

    public func artwork(for trackID: UInt64?) -> CGImage? { covers.image(for: trackID) }

    /// Decodes artwork if it is not there yet. Safe to call repeatedly.
    public func ensureArtwork(for trackID: UInt64?) async { await covers.ensure(trackID) }

    /// Tracks of the current version of a card - a card from the view may be from before an edit.
    /// An album that no longer exists has no tracks.
    public func tracks(of album: AlbumCard) -> [TrackRow] {
        guard let library, let album = current(album) else { return [] }
        let all = library.tracks
        // From the card's positions, not by name: an album split into two blocks shows
        // its own tracks in each card instead of pretending to be empty.
        let rows = album.trackIndices.compactMap { $0 < all.count ? all[$0] : nil }
        return rows.map { track in
            TrackRow(id: track.uniqueID, persistentID: track.persistentID,
                     title: track.title ?? "", artist: track.artist ?? "",
                     number: track.trackNumber, duration: track.duration,
                     playCount: track.playCount,
                     fileMissing: missingFileIDs.contains(track.uniqueID),
                     formatVerdict: formatVerdicts[track.uniqueID],
                     formatLabel: formatLabels[track.uniqueID])
        }
    }

    public func index(of album: AlbumCard) -> Int? { catalog.index(of: album) }

    /// The current version of a card (`AlbumCatalog.current`) - after an edit the cards are
    /// rebuilt; `nil` when no track of the album is left.
    public func current(_ album: AlbumCard) -> AlbumCard? { catalog.current(album) }

    /// The audio file URL; a snapshot without a Music folder does not allow previewing.
    public func fileURL(for track: TrackRow) -> URL? {
        guard canCheckFiles, let paths,
              let record = library?.tracks.first(where: { $0.uniqueID == track.id }) else { return nil }
        return record.fileURL(on: paths)
    }

    // MARK: - Editing (commands in `Editing/`)

    /// How many of the album's files will really disappear from disk - for the confirmation text.
    public func deletableFileCount(of album: AlbumCard) -> Int {
        guard let library, let paths, let album = current(album) else { return 0 }
        let all = library.tracks
        return album.trackIndices.compactMap { $0 < all.count ? all[$0] : nil }
            .filter { record in
                guard let url = record.fileURL(on: paths) else { return false }
                return DeviceFiles.isDeletableAudioFile(url, under: paths.musicDirectory, files: environment.files)
            }.count
    }

    /// The device disappeared from under us - the volume was unmounted.
    /// There is no point keeping the library in memory: it can be neither written
    /// nor its files played, and showing it suggests the iPod is still there.
    ///
    /// We ask about `iPod_Control`, not about the mount folder itself - the same condition
    /// works for a volume and for an iPod in a plain folder (a fake in tests).
    public func deviceDisconnected() -> Bool {
        guard case .device(let device)? = source,
              !environment.files.fileExists(at: device.paths.control) else { return false }
        let lost = changes.log.count
        generation += 1
        session = nil
        formats = FormatReport()
        covers.clear()
        catalog = .empty
        preflightState = nil
        changes = ChangeSet()
        refreshPendingAlbums()
        state = lost > 0 ? .failed(.disconnected(unsavedChanges: lost)) : .empty
        return true
    }

    // MARK: - Writing

    /// The last failed write - for the diagnostic report, which the user
    /// copies and sends themselves. Cleared on a successful write.
    public private(set) var lastWriteFailure: String?
    /// What the last successful write in this session did - counts and error causes,
    /// without titles. For the diagnostic report.
    public private(set) var lastWriteSummary: [String] = []

    /// Writes the changes to the iPod (`WriteTransaction`). The model takes over the result
    /// only after a successful write; after an error the library and the change queue
    /// stay as they were before the write.
    public func apply() async throws -> WriteOutcome {
        do {
            if writesBlocked { throw WriteBlocked.demoCopy }
            guard state == .loaded, let device, let library else {
                throw WriteBlocked.notFromDevice
            }
            guard permissions.policy(for: device) == device.writePolicy else { throw WriteBlocked.permissionChanged }
            var transaction = WriteTransaction(library: library, changes: changes, device: device, capabilities: capabilities,
                                               environment: environment, note: "Clickwill: \(changes.log.count) changes")
            transaction.expectedSourceDigest = sourceDigest
            transaction.backupReason = .beforeWrite(changes: changes.log.count)
            transaction.backupRetention = backupRetention
            transaction.backupRetention.pinned = permissions.pinnedBackups(for: device)
            let changeCount = changes.log.count
            let result = try await transaction.run()
            if device.writesOutsideConfirmedModels && device.writePolicy == .experimental {
                permissions.recordWrite(on: device, changes: changeCount, backupID: result.outcome.result.snapshot.id)
            }
            adopt(result, from: device)
            lastWriteFailure = nil
            lastWriteSummary = result.outcome.summary
            return result.outcome
        } catch {
            lastWriteFailure = "\(error)"
            throw error
        }
    }

    /// The state after a successful write: the library as it went to disk, and what
    /// from the queue did not go in.
    private func adopt(_ result: WriteTransaction.Result, from device: IPodDevice) {
        session?.adopt(result.writtenLibrary, sourceDigest: result.sourceDigest, filesReplaced: result.filesReplaced)
        changes = result.remaining
        for (id, image) in result.coverImages { covers.show(image, for: [id]) }
        if result.artworkChanged { replaceArtwork(try? device.readArtwork()) }
        if result.filesReplaced { startFormatScan() }
        rebuildCards()
        refreshPreflight()
    }


    public func preflight() -> WritePreflight? { preflightState }
}
