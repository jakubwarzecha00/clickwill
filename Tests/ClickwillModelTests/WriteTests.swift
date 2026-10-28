import Foundation
import CoreGraphics
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// A successful write to the iPod through `LibraryModel.apply()` - on a fake signed
/// iPod in a temporary folder. Characterization tests: they record the current
/// behavior before the write transaction is broken into parts.
@Suite("Writing to the iPod")
@MainActor
struct WriteTests {

    /// The fake's GUID. The database is signed with it, and `SysInfoExtended` gives it -
    /// as on an iPod that was once connected to a Mac.
    nonisolated static let guid = "000A270011223344"

    /// What the fake should have apart from the signed database and the files in Music.
    struct Fixture {
        var musicRunning = false
        /// Artwork for the album Aftermath (format 1027), added the same way the
        /// app adds first artwork.
        var cover = false
        /// "Eventually" (16) is named like "Let It Happen" (15) - a duplicate.
        var duplicate = false
        /// A track without a file in Music.
        var missingFile: UInt32? = nil
        /// A track with a WAV 24 bit / 96 kHz file - to convert.
        var hiRes: UInt32? = nil
        /// A track with the artwork marker (0x7E) zeroed by an old generator bug
        /// (described in `TrackArtworkFields`).
        var brokenMarker: UInt32? = nil
        /// A track whose path in the database points to the `F00` folder with the files
        /// of the other tracks - a path from the database is not trusted.
        var pointsAtFolder: UInt32? = nil
        /// The fake's GUID - a different one when a test needs two different iPods.
        var guid = WriteTests.guid
    }

    /// A fake iPod classic: a signed database, a file in Music for every track,
    /// backups and the order intent in the same temporary folder.
    @MainActor
    struct Rig {
        let root: URL
        let paths: IPodPaths
        let environment: LibraryEnvironment
        let model: LibraryModel

        var backups: SnapshotStore { get throws { try environment.backups() } }

        func onDisk() throws -> ITLibrary { try ITunesDBParser.parse(Data(contentsOf: paths.iTunesDB)) }

        func artworkOnDisk() throws -> ArtworkLibrary { try ArtworkDBParser.parse(Data(contentsOf: paths.artworkDB)) }

        func signedWithDeviceKey() throws -> Bool {
            FireWireGUID.signs(try Hash58.fireWireID(fromHex: WriteTests.guid), try Data(contentsOf: paths.iTunesDB))
        }

        func album(_ title: String) throws -> AlbumCard {
            try #require(model.albums.first { $0.title == title })
        }

        func row(_ title: String, in album: String) throws -> TrackRow {
            try #require(model.tracks(of: try self.album(album)).first { $0.title == title })
        }

        func musicFile(_ id: Int, _ ext: String = "mp3") -> URL {
            paths.musicDirectory.appendingPathComponent("F00/\(id).\(ext)")
        }

        func musicFiles() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: paths.musicDirectory.appendingPathComponent("F00").path))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    static func rig(_ fixture: Fixture = Fixture()) async throws -> Rig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-write-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root.appendingPathComponent("iPod", isDirectory: true))
        let manager = FileManager.default
        try manager.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.musicDirectory.appendingPathComponent("F00"), withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.sysInfoExtended.deletingLastPathComponent(), withIntermediateDirectories: true)

        var titles: [UInt32: String] = [:]
        if fixture.duplicate { titles[16] = "Let It Happen" }
        var extensions: [UInt32: String] = [:]
        if let id = fixture.hiRes { extensions[id] = "wav" }
        // Records described as MP3 and with the artwork marker, like records from iTunes:
        // a new track is created on the template of a record of the same format.
        var library = try ITunesDBParser.parse(SyntheticLibrary.database(titles: titles, extensions: extensions))
            .mappingTracks { track in
                let kind: TrackFileKind = track.uniqueID == fixture.hiRes ? .wav : .mp3
                var typed = track.settingFileKind(kind)
                if track.uniqueID == fixture.pointsAtFolder { typed = typed.setting(.location, to: ":iPod_Control:Music:F00") }
                return track.uniqueID == fixture.brokenMarker ? typed : typed.restoringArtworkMarker()
            }
        if fixture.cover {
            let owner = try #require(library.tracks.first { $0.album == "Aftermath" })
            _ = try ArtworkAddition.add(ownerPersistentID: owner.persistentID, sourceByteCount: 5000, trackCount: 2, in: paths,
                                        deviceFormats: [.init(formatID: 1027, width: 100, height: 100, pixelFormat: "L565")]) { w, h in
                try ITHMBImage(rendering: Self.image(red: 1, green: 0, blue: 0), width: w, height: h)
            }
            library = library.linkingAlbumArtwork(album: "Aftermath", ownerPersistentID: owner.persistentID)
                .markingAlbumArtwork(album: "Aftermath", sourceByteCount: 5000)
        }
        try Hash58.sign(ITunesDBWriter.serialize(library), fireWireID: Hash58.fireWireID(fromHex: fixture.guid)).write(to: paths.iTunesDB)
        try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>FireWireGUID</key><string>\(fixture.guid)</string></dict></plist>
            """.utf8).write(to: paths.sysInfoExtended)
        for id in UInt32(10)...16 where id != fixture.missingFile {
            if id == fixture.hiRes {
                try Self.wave(bitDepth: 24, sampleRate: 96_000).write(to: paths.musicDirectory.appendingPathComponent("F00/\(id).wav"))
            } else {
                try Data(repeating: UInt8(id), count: 1000).write(to: paths.musicDirectory.appendingPathComponent("F00/\(id).mp3"))
            }
        }

        var environment = LibraryEnvironment.isolated(in: root.appendingPathComponent("Support", isDirectory: true))
        environment.isMusicRunning = { fixture.musicRunning }
        let volume = try #require(IPodVolume.at(paths.mountPoint))
        let device = try IPodDevice.open(volume)
        #expect(device.supportsWriting, "the fake must accept writing: \(device.readOnlyReason?.description ?? "")")

        let model = LibraryModel(environment: environment)
        await model.load(.device(device))
        #expect(model.state == .loaded)
        return Rig(root: root, paths: paths, environment: environment, model: model)
    }

    /// A uniform square in the given color.
    nonisolated static func image(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return try #require(context.makeImage())
    }

    /// A WAV file (PCM, stereo, 0.2 s of silence).
    nonisolated static func wave(bitDepth: Int, sampleRate: Int) -> Data {
        let channels = 2, frames = sampleRate / 5
        let blockAlign = channels * bitDepth / 8
        let dataSize = frames * blockAlign
        var data = Data()
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(channels); u32(sampleRate)
        u32(sampleRate * blockAlign); u16(blockAlign); u16(bitDepth)
        data.append(contentsOf: Array("data".utf8)); u32(dataSize)
        data.append(Data(count: dataSize))
        return data
    }

    @Test("an album rename: the database on the iPod signed, a backup, the changes cleared")
    func renameAlbum() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        #expect(rig.model.hasPendingChanges)

        let outcome = try await rig.model.apply()

        let disk = try rig.onDisk()
        #expect(Set(disk.tracks.filter { $0.album == "Currents (Deluxe)" }.map(\.title)) == ["Let It Happen", "Eventually"])
        #expect(!disk.tracks.contains { $0.album == "Currents" })
        #expect(try rig.signedWithDeviceKey())
        #expect(!outcome.result.identicalToPrevious)
        #expect(outcome.orderIntentSaved)
        #expect(FileManager.default.fileExists(
            atPath: try OrderIntentStore(root: rig.root.appendingPathComponent("Support/Devices")).url(forDevice: Self.guid).path))
        #expect(try rig.backups.list(deviceGUID: Self.guid).map(\.reason) == [.beforeWrite(changes: 1)], "a backup before the database write")

        #expect(!rig.model.hasPendingChanges)
        #expect(rig.model.albums.contains { $0.title == "Currents (Deluxe)" })
        #expect(rig.model.library?.tracks.map(\.album) == disk.tracks.map(\.album), "the model after the write = the database on disk")
        #expect(rig.model.lastWriteFailure == nil)
        #expect(rig.model.lastWriteSummary.first?.hasPrefix("Last write:") == true)
    }

    @Test("a removed track: it disappears from the database, and its file from Music only after the write")
    func deleteTrack() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let bends = try rig.album("The Bends")
        let bones = try #require(rig.model.tracks(of: bends).first { $0.title == "Bones" })
        try rig.model.deleteTrack(bones, in: bends)
        #expect(FileManager.default.fileExists(atPath: rig.musicFile(10).path), "before the write the file stays")

        let outcome = try await rig.model.apply()

        #expect(try rig.onDisk().tracks.count == 6)
        #expect(!(try rig.onDisk().tracks.contains { $0.title == "Bones" }))
        #expect(outcome.deletedFiles == 1)
        #expect(outcome.undeletedFiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.musicFile(10).path))
        #expect(FileManager.default.fileExists(atPath: rig.musicFile(12).path), "the other files untouched")
    }

    @Test("a record pointing to a folder in Music: it disappears from the database, the folder and the other tracks' files stay")
    func deleteTrackPointingAtFolder() async throws {
        let rig = try await Self.rig(Fixture(pointsAtFolder: 10)); defer { rig.cleanUp() }
        let filesBefore = try rig.musicFiles()
        let bends = try rig.album("The Bends")
        let bones = try #require(rig.model.tracks(of: bends).first { $0.title == "Bones" })
        try rig.model.deleteTrack(bones, in: bends)
        #expect(rig.model.changes.filesToDelete.isEmpty, "the folder does not go into the deletion queue")

        let outcome = try await rig.model.apply()

        #expect(!(try rig.onDisk().tracks.contains { $0.title == "Bones" }))
        #expect(outcome.deletedFiles == 0)
        #expect(try rig.musicFiles() == filesBefore)
    }

    /// The same path as `ipodctl remove`: the removal plan in `ChangeSet`, the write
    /// through the transaction, without the window model.
    @Test("removal through the transaction (ipodctl): the folder neither goes into the queue nor disappears")
    func transactionKeepsFolderOfRemovedRecord() async throws {
        let rig = try await Self.rig(Fixture(pointsAtFolder: 10)); defer { rig.cleanUp() }
        let device = try #require(rig.model.device)
        let filesBefore = try rig.musicFiles()
        let database = try Data(contentsOf: rig.paths.iTunesDB)
        let library = try ITunesDBParser.parse(database)
        let updated = try library.removingTracks(uniqueIDs: [10])
        var changes = ChangeSet()
        let queued = changes.queueFiles(of: library.tracks.filter { $0.uniqueID == 10 }, keeping: updated,
                                        paths: rig.paths, files: LocalFileSystem(), keepCopiesIn: nil)
        #expect(queued.isEmpty)
        var transaction = WriteTransaction(library: updated, changes: changes, device: device,
                                           capabilities: IPodCapabilities.resolve(format: device.format, model: device.model),
                                           environment: rig.environment, note: "test")
        transaction.expectedSourceDigest = IPodDevice.digest(of: database)

        let result = try await transaction.run()

        #expect(!(try rig.onDisk().tracks.contains { $0.uniqueID == 10 }))
        #expect(result.outcome.deletedFiles == 0)
        #expect(try rig.musicFiles() == filesBefore)
    }

    @Test("a folder in the deletion queue despite the rule: the after-write phase checks again and leaves it")
    func afterWriteKeepsFolder() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let device = try #require(rig.model.device)
        let filesBefore = try rig.musicFiles()
        let folder = rig.paths.musicDirectory.appendingPathComponent("F00")

        var ledger = WriteLedger()
        AfterWritePhase(filesToDelete: [folder], archiveBeforeDelete: [:], replacements: [:], files: LocalFileSystem())
            .run(on: device, ledger: &ledger)

        #expect(ledger.deletedFiles == 0)
        #expect(ledger.keptFiles == [folder])
        #expect(ledger.completed.deletionsToRetry.isEmpty, "the rule will reject it on the next write too - we do not retry")
        #expect(try rig.musicFiles() == filesBefore)
    }

    @Test("the track order in an album reaches the database")
    func reorderTracks() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let bends = try rig.album("The Bends")
        #expect(rig.model.tracks(of: bends).map(\.title) == ["Planet Telex", "Bones", "Just"])
        try rig.model.moveTracks(in: bends, fromOffsets: IndexSet(integer: 2), toOffset: 0)

        _ = try await rig.model.apply()

        let reloaded = LibraryModel(environment: rig.environment)
        let device = try IPodDevice.open(try #require(IPodVolume.at(rig.paths.mountPoint)))
        await reloaded.load(.device(device))
        let album = try #require(reloaded.albums.first { $0.title == "The Bends" })
        #expect(reloaded.tracks(of: album).map(\.title) == ["Just", "Planet Telex", "Bones"])
    }

    @Test("an added track: the file in Music, the entry in the database, the queue empty")
    func addTrack() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let source = rig.root.appendingPathComponent("only-shallow.mp3")
        try Data(repeating: 7, count: 4000).write(to: source)
        let draft = TrackDraft(title: "Only Shallow", artist: "My Bloody Valentine", albumArtist: "My Bloody Valentine",
                               album: "Loveless", sizeBytes: 4000, kind: .mp3, relativePath: "")
        let refused = rig.model.queueAdditions([AudioImport.Candidate(url: source, draft: draft, verdict: .supported,
                                                             formatLabel: "MP3", artwork: nil)])
        #expect(refused.isEmpty)

        let outcome = try await rig.model.apply()

        #expect(outcome.addedTracks == 1)
        #expect(outcome.additionProblems.isEmpty, "\(outcome.additionProblems)")
        let added = try #require(try rig.onDisk().tracks.first { $0.title == "Only Shallow" })
        #expect(added.album == "Loveless")
        let file = try #require(added.fileURL(on: rig.paths))
        #expect(try Data(contentsOf: file) == Data(repeating: 7, count: 4000))
        #expect(rig.model.changes.additions.isEmpty)
        #expect(!rig.model.hasPendingChanges)
        #expect(try rig.signedWithDeviceKey())
    }

    @Test("Music open: the write rejected, the database and the changes unchanged")
    func refusedWhileMusicRuns() async throws {
        let rig = try await Self.rig(Fixture(musicRunning: true)); defer { rig.cleanUp() }
        let before = try Data(contentsOf: rig.paths.iTunesDB)
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")

        await #expect(throws: ITDBError.self) { _ = try await rig.model.apply() }

        #expect(try Data(contentsOf: rig.paths.iTunesDB) == before)
        #expect(rig.model.hasPendingChanges, "a rejected write does not lose the changes")
        #expect(rig.model.lastWriteFailure != nil)
        #expect(try rig.backups.list(deviceGUID: Self.guid).isEmpty, "a refusal before the backup")
    }

    @Test("Music open: a refusal before the repairs that would write ArtworkDB - no backup and no changes on the iPod")
    func musicRefusedBeforeRepairs() async throws {
        let rig = try await Self.rig(Fixture(musicRunning: true, cover: true)); defer { rig.cleanUp() }
        let artwork = try Data(contentsOf: rig.paths.artworkDB)
        // The album loses a track - the artwork coverage would have to be fixed in ArtworkDB.
        try rig.model.deleteTrack(try rig.row("Paint It Black", in: "Aftermath"), in: try rig.album("Aftermath"))

        await #expect(throws: ITDBError.self) { _ = try await rig.model.apply() }

        #expect(try Data(contentsOf: rig.paths.artworkDB) == artwork)
        #expect(try rig.backups.list(deviceGUID: Self.guid).isEmpty, "a refusal before the first change, so no backup")
    }

    @Test("an unreadable ArtworkDB: the artwork repair step does not pretend there was nothing to repair")
    func unreadableArtworkReported() async throws {
        let rig = try await Self.rig(Fixture(cover: true)); defer { rig.cleanUp() }
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        try Data("this is not an ArtworkDB".utf8).write(to: rig.paths.artworkDB)

        let outcome = try await rig.model.apply()

        #expect(outcome.repairs.problems.contains { $0.step == .imageLinks }, "\(outcome.repairs.problems)")
        #expect(try rig.onDisk().tracks.contains { $0.album == "Currents (Deluxe)" }, "the database written anyway")
    }

    @Test("the order intent from the written library, with the added tracks")
    func intentIncludesAddedTracks() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let source = rig.root.appendingPathComponent("only-shallow.mp3")
        try Data(repeating: 7, count: 4000).write(to: source)
        let draft = TrackDraft(title: "Only Shallow", artist: "My Bloody Valentine", albumArtist: "My Bloody Valentine",
                               album: "Loveless", sizeBytes: 4000, kind: .mp3, relativePath: "")
        _ = rig.model.queueAdditions([AudioImport.Candidate(url: source, draft: draft, verdict: .supported, formatLabel: "MP3", artwork: nil)])

        let outcome = try await rig.model.apply()

        #expect(outcome.orderIntentSaved)
        let store = OrderIntentStore(root: rig.root.appendingPathComponent("Support/Devices"))
        let intent = try #require(try store.load(deviceGUID: Self.guid))
        #expect(intent.albums.contains("Loveless"), "\(intent.albums)")
        #expect(intent.tracks["Loveless"]?.count == 1)
    }

    @Test("the database on the iPod changed since loading: the write rejected, the other database untouched")
    func refusedWhenDatabaseChangedOnDevice() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        // Someone else (Music) rewrote the database after loading.
        var foreign = try rig.onDisk()
        foreign = try foreign.removingTracks(uniqueIDs: Set([16]))
        let rewritten = try Hash58.sign(ITunesDBWriter.serialize(foreign), fireWireID: Hash58.fireWireID(fromHex: Self.guid))
        try rewritten.write(to: rig.paths.iTunesDB)

        let filesBefore = try rig.musicFiles()
        let source = rig.root.appendingPathComponent("only-shallow.mp3")
        try Data(repeating: 7, count: 4000).write(to: source)
        let draft = TrackDraft(title: "Only Shallow", artist: "My Bloody Valentine", albumArtist: "My Bloody Valentine",
                               album: "Loveless", sizeBytes: 4000, kind: .mp3, relativePath: "")
        _ = rig.model.queueAdditions([AudioImport.Candidate(url: source, draft: draft, verdict: .supported, formatLabel: "MP3", artwork: nil)])

        await #expect(throws: ITDBError.self) { _ = try await rig.model.apply() }

        #expect(try Data(contentsOf: rig.paths.iTunesDB) == rewritten)
        #expect(rig.model.hasPendingChanges)
        #expect(try rig.musicFiles() == filesBefore, "a refusal before the first file")
        #expect(try rig.backups.list(deviceGUID: Self.guid).isEmpty, "a refusal before the backup")
    }

    @Test("an album's first artwork: a new image in ArtworkDB, owned by the album's first track")
    func coverAdded() async throws {
        let rig = try await Self.rig(Fixture(cover: true)); defer { rig.cleanUp() }
        #expect(try rig.artworkOnDisk().images.count == 1)
        let bends = try rig.album("The Bends")
        try rig.model.setArtwork(for: bends, image: try Self.image(red: 0, green: 0, blue: 1), sourceByteCount: 7000)

        let outcome = try await rig.model.apply()

        #expect(outcome.coversWritten == 1)
        #expect(outcome.coversFailed.isEmpty)
        let images = try rig.artworkOnDisk().images
        #expect(images.count == 2)
        let owners = Set(images.map(\.trackPersistentID))
        let bendsIDs = Set(try rig.onDisk().tracks.filter { $0.album == "The Bends" }.map(\.persistentID))
        #expect(!owners.isDisjoint(with: bendsIDs), "the new image belongs to a track from The Bends")
        #expect(rig.model.artwork?.images.count == 2, "the model reads ArtworkDB after the write")
        #expect(try rig.signedWithDeviceKey())
        #expect(Set(try rig.backups.list(deviceGUID: Self.guid).map(\.reason)) == [.beforeFiles, .beforeWrite(changes: 1)],
                "a backup before the artwork and before the database, each with its own reason")
    }

    /// `ipodctl artwork --per-track`: the nano 2G looks up artwork by track.
    @Test("the album image for another track: a new mhii with the same slices, coverage settled")
    func coverShared() async throws {
        let rig = try await Self.rig(Fixture(cover: true)); defer { rig.cleanUp() }
        let device = try #require(rig.model.device)
        let database = try Data(contentsOf: rig.paths.iTunesDB)
        let library = try ITunesDBParser.parse(database)
        let tracks = library.tracks.filter { $0.album == "Aftermath" }
        let image = try #require(try rig.artworkOnDisk().images.first)
        let other = try #require(tracks.first { $0.persistentID != image.trackPersistentID })
        var changes = ChangeSet()
        changes.queueCoverSharing(imageID: image.id, with: [other], album: "Aftermath", for: AlbumID(albumOf: tracks))
        var transaction = WriteTransaction(library: library, changes: changes, device: device,
                                           capabilities: IPodCapabilities.resolve(format: device.format, model: device.model),
                                           environment: rig.environment, note: "test")
        transaction.expectedSourceDigest = IPodDevice.digest(of: database)

        let result = try await transaction.run()

        #expect(result.outcome.coversWritten == 1)
        #expect(result.remaining.artworkSharing.isEmpty)
        let images = try rig.artworkOnDisk().images
        #expect(images.count == 2)
        let shared = try #require(images.first { $0.trackPersistentID == other.persistentID })
        #expect(shared.variants.map(\.byteOffset) == image.variants.map(\.byteOffset), "the same slices")
        #expect(result.outcome.repairs.coverage.count == 1, "two images with 1 track each instead of 2 + 1")
        #expect(result.sourceDigest == IPodDevice.digest(of: try Data(contentsOf: rig.paths.iTunesDB)),
                "the digest from the bytes written and read back from the medium")
        #expect(try rig.backups.list(deviceGUID: Self.guid).count == 2, "a backup before the artwork and before the database")
    }

    @Test("an artwork replacement: the same slices, new pixels, no new image")
    func coverReplaced() async throws {
        let rig = try await Self.rig(Fixture(cover: true)); defer { rig.cleanUp() }
        let ithmb = try #require(try FileManager.default.contentsOfDirectory(at: rig.paths.artworkDirectory,
                                                                              includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "ithmb" })
        let before = try Data(contentsOf: ithmb)
        try rig.model.setArtwork(for: try rig.album("Aftermath"), image: try Self.image(red: 0, green: 1, blue: 0))

        let outcome = try await rig.model.apply()

        #expect(outcome.coversWritten == 1)
        #expect(try rig.artworkOnDisk().images.count == 1)
        #expect(try Data(contentsOf: ithmb) != before)
        #expect(!rig.model.hasPendingChanges)
    }

    @Test("a zeroed artwork marker (0x7E) is repaired on every write")
    func markerRepaired() async throws {
        let rig = try await Self.rig(Fixture(brokenMarker: 12)); defer { rig.cleanUp() }
        #expect(!(try #require(try rig.onDisk().tracks.first { $0.uniqueID == 12 }).hasArtworkMarker))
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")

        let outcome = try await rig.model.apply()

        #expect(outcome.repairs.artworkMarkers == 1)
        #expect(try rig.onDisk().tracks.allSatisfy(\.hasArtworkMarker))
        #expect(rig.model.lastWriteSummary.contains { $0.contains("artwork markers 1") })
    }

    @Test("merging duplicates: one copy stays, the other's file deleted")
    func duplicatesMerged() async throws {
        let rig = try await Self.rig(Fixture(duplicate: true)); defer { rig.cleanUp() }
        let groups = rig.model.duplicateGroups()
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(Set([group.keep.id] + group.remove.map(\.id)) == [15, 16])
        _ = try rig.model.mergeDuplicates(groups)

        let outcome = try await rig.model.apply()

        let disk = try rig.onDisk()
        #expect(disk.tracks.count == 6)
        #expect(disk.tracks.filter { $0.title == "Let It Happen" }.map(\.uniqueID) == [group.keep.id])
        #expect(outcome.deletedFiles == 1)
        let removed = try #require(group.remove.first).id
        #expect(!FileManager.default.fileExists(atPath: rig.musicFile(Int(removed)).path))
        #expect(FileManager.default.fileExists(atPath: rig.musicFile(Int(group.keep.id)).path))
    }

    @Test("a restored file: it goes into Music, the entry points to it, the track stops being missing")
    func missingFileRestored() async throws {
        let rig = try await Self.rig(Fixture(missingFile: 16)); defer { rig.cleanUp() }
        #expect(rig.model.missingFileIDs == [16])
        let source = rig.root.appendingPathComponent("eventually.mp3")
        try Data(repeating: 9, count: 3000).write(to: source)
        let candidate = ImportCandidate(url: source, verdict: .supported, formatLabel: "MP3", durationMilliseconds: 180_000,
                                        taggedTitle: "Eventually", trackNumber: 2, sizeBytes: 3000, bitRate: 256,
                                        sampleRate: 44_100, kind: .mp3)
        try rig.model.importFile(candidate, for: try rig.row("Eventually", in: "Currents"), in: try rig.album("Currents"))

        let outcome = try await rig.model.apply()

        #expect(outcome.restoredFiles == 1)
        #expect(outcome.restoreProblems.isEmpty, "\(outcome.restoreProblems)")
        let track = try #require(try rig.onDisk().tracks.first { $0.uniqueID == 16 })
        let file = try #require(track.fileURL(on: rig.paths))
        #expect(try Data(contentsOf: file) == Data(repeating: 9, count: 3000))
        #expect(rig.model.missingFileIDs.isEmpty)
    }

    @Test("a 24 bit / 96 kHz conversion: a new file on the iPod, the old one deleted after the database write")
    func trackConverted() async throws {
        let rig = try await Self.rig(Fixture(hiRes: 14)); defer { rig.cleanUp() }
        await rig.model.formatScan?.value
        let verdict = try #require(rig.model.formatVerdicts[14])
        #expect(!verdict.isSupported, "the iPod will not play WAV 24/96")
        try rig.model.convertTrack(try rig.row("Just", in: "The Bends"), in: try rig.album("The Bends"), keepOriginalsIn: nil)

        let outcome = try await rig.model.apply()

        #expect(outcome.convertedFiles == 1)
        #expect(outcome.conversionProblems.isEmpty, "\(outcome.conversionProblems)")
        #expect(!FileManager.default.fileExists(atPath: rig.musicFile(14, "wav").path))
        let track = try #require(try rig.onDisk().tracks.first { $0.uniqueID == 14 })
        let file = try #require(track.fileURL(on: rig.paths))
        #expect(file.pathExtension != "wav")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a partly successful write: a failed conversion stays in the queue with its entry, the written change leaves the list")
    func failedConversionStaysListed() async throws {
        let rig = try await Self.rig(Fixture(hiRes: 14)); defer { rig.cleanUp() }
        await rig.model.formatScan?.value
        try rig.model.convertTrack(try rig.row("Just", in: "The Bends"), in: try rig.album("The Bends"), keepOriginalsIn: nil)
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        // The file breaks between the request and the write - the conversion will not go in.
        try Data("this is not a WAV".utf8).write(to: rig.musicFile(14, "wav"))

        let outcome = try await rig.model.apply()

        #expect(outcome.convertedFiles == 0)
        #expect(outcome.conversionProblems.count == 1)
        #expect(try rig.onDisk().tracks.contains { $0.album == "Currents (Deluxe)" }, "the rest written")
        #expect(rig.model.hasPendingChanges)
        #expect(rig.model.changes.log.count == 1, "\(rig.model.changes.log.map(\.kind))")
        guard case .trackConverted(_, "Just", _, _, _)? = rig.model.changes.log.first?.kind else {
            Issue.record("\(rig.model.changes.log.map(\.kind))"); return
        }
    }

    @Test("a rejected database write: the files added in this transaction cleaned up")
    func failedWriteRemovesCopiedFiles() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let filesBefore = try rig.musicFiles()
        let source = rig.root.appendingPathComponent("only-shallow.mp3")
        try Data(repeating: 7, count: 4000).write(to: source)
        let draft = TrackDraft(title: "Only Shallow", artist: "My Bloody Valentine", albumArtist: "My Bloody Valentine",
                               album: "Loveless", sizeBytes: 4000, kind: .mp3, relativePath: "")
        _ = rig.model.queueAdditions([AudioImport.Candidate(url: source, draft: draft, verdict: .supported, formatLabel: "MP3", artwork: nil)])
        // Play Counts that cannot be matched: the writer refuses only at the database,
        // already after the file was copied.
        try Data(repeating: 0, count: 96).write(to: rig.paths.playCounts)
        let database = try Data(contentsOf: rig.paths.iTunesDB)

        await #expect(throws: (any Error).self) { _ = try await rig.model.apply() }

        #expect(try rig.musicFiles() == filesBefore, "the copied file removed, because the database does not point to it")
        #expect(try Data(contentsOf: rig.paths.iTunesDB) == database)
        // The model after a rejected write is as it was before it.
        #expect(rig.model.changes.additions.count == 1, "the track did not reach the iPod, so it keeps waiting")
        #expect(!(rig.model.library?.tracks.contains { $0.title == "Only Shallow" } ?? true),
                "the model does not show a track that is not in the database")
        #expect(rig.model.hasPendingChanges)
    }

    @Test("a disconnected iPod: all pending changes discarded, restored files included")
    func disconnectDropsEveryQueue() async throws {
        let rig = try await Self.rig(Fixture(missingFile: 16)); defer { rig.cleanUp() }
        let source = rig.root.appendingPathComponent("eventually.mp3")
        try Data(repeating: 9, count: 3000).write(to: source)
        let candidate = ImportCandidate(url: source, verdict: .supported, formatLabel: "MP3", durationMilliseconds: 180_000,
                                        taggedTitle: "Eventually", trackNumber: 2, sizeBytes: 3000, bitRate: 256,
                                        sampleRate: 44_100, kind: .mp3)
        try rig.model.importFile(candidate, for: try rig.row("Eventually", in: "Currents"), in: try rig.album("Currents"))
        let draft = TrackDraft(title: "Only Shallow", artist: "My Bloody Valentine", albumArtist: "My Bloody Valentine",
                               album: "Loveless", sizeBytes: 4000, kind: .mp3, relativePath: "")
        _ = rig.model.queueAdditions([AudioImport.Candidate(url: source, draft: draft, verdict: .supported, formatLabel: "MP3", artwork: nil)])
        try rig.model.deleteTrack(try rig.row("Bones", in: "The Bends"), in: try rig.album("The Bends"))
        #expect(!rig.model.changes.fileImports.isEmpty && !rig.model.changes.additions.isEmpty)

        try FileManager.default.removeItem(at: rig.paths.control)
        #expect(rig.model.deviceDisconnected())

        let changes = rig.model.changes
        #expect(changes.log.isEmpty && changes.additions.isEmpty && changes.fileImports.isEmpty)
        #expect(changes.filesToDelete.isEmpty && changes.archiveBeforeDelete.isEmpty && changes.conversions.isEmpty)
        #expect(changes.artworkAdditions.isEmpty && changes.artworkReplacements.isEmpty)
        #expect(changes.playCountRedirects.isEmpty && changes.artworkOwnerRedirects.isEmpty)
        #expect(rig.model.coverFlowDisplay.isEmpty, "the pending album disappears together with the queue")
    }

    @Test("a rejected database write after new artwork: ArtworkDB and the artwork files come back from the backup")
    func failedWriteRestoresArtwork() async throws {
        let rig = try await Self.rig(Fixture(cover: true)); defer { rig.cleanUp() }
        let artworkFiles = { () throws -> [String: Data] in
            let urls = try FileManager.default.contentsOfDirectory(at: rig.paths.artworkDirectory, includingPropertiesForKeys: nil)
            return Dictionary(uniqueKeysWithValues: try urls.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
        }
        let before = try artworkFiles()
        try rig.model.setArtwork(for: try rig.album("The Bends"), image: try Self.image(red: 0, green: 0, blue: 1))
        // A Play Counts file that cannot be matched to the database: the gates before
        // the files let it through (the writer merges plays itself), and the writer
        // refuses only at the database write - already after the new artwork.
        try Data(repeating: 0, count: 96).write(to: rig.paths.playCounts)

        await #expect(throws: (any Error).self) { _ = try await rig.model.apply() }

        let after = try artworkFiles()
        #expect(after == before, "different: \(Set(after.keys).union(before.keys).filter { after[$0] != before[$0] }.sorted())")
        #expect(rig.model.changes.artworkAdditions.count == 1, "the artwork keeps waiting")
    }

    @Test("the write summary for the diagnostic report")
    func writeSummary() async throws {
        let rig = try await Self.rig(Fixture(brokenMarker: 12)); defer { rig.cleanUp() }
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        _ = try await rig.model.apply()
        #expect(rig.model.lastWriteSummary == [
            "Last write: covers written 0, covers failed 0, songs added 0, files deleted 0, files converted 0",
            "  repaired while writing: artwork markers 1",
        ])
    }
}
