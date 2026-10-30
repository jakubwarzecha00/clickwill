import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Writing to an unconfirmed model (`WritePolicy.experimental`) through `LibraryModel`: an
/// iPod Video fake with an unsigned database. What may change, and what the write leaves alone.
@Suite("Writing to an experimental iPod")
@MainActor
struct ExperimentalWriteTests {

    @MainActor
    struct Rig {
        let root: URL
        let paths: IPodPaths
        let environment: LibraryEnvironment
        let model: LibraryModel

        func onDisk() throws -> ITLibrary { try ITunesDBParser.parse(Data(contentsOf: paths.iTunesDB)) }
        func musicFile(_ id: Int) -> URL { paths.musicDirectory.appendingPathComponent("F00/\(id).mp3") }
        func album(_ title: String) throws -> AlbumCard { try #require(model.albums.first { $0.title == title }) }
        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    /// - Parameters:
    ///   - brokenMarker: a track whose artwork marker (0x7E) is zeroed - a repair would set it.
    ///   - cover: artwork for Aftermath in format 1027, without the 0x160 pointer a repair would set.
    static func rig(policy: WritePolicy = .experimental, brokenMarker: UInt32? = nil, cover: Bool = false) async throws -> Rig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clickwill-experimental-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root.appendingPathComponent("iPod", isDirectory: true))
        let manager = FileManager.default
        try manager.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: paths.musicDirectory.appendingPathComponent("F00"), withIntermediateDirectories: true)

        var library = try ITunesDBParser.parse(SyntheticLibrary.database()).mappingTracks { track in
            let typed = track.settingFileKind(.mp3)
            return track.uniqueID == brokenMarker ? typed : typed.restoringArtworkMarker()
        }
        if cover {
            let owner = try #require(library.tracks.first { $0.album == "Aftermath" })
            _ = try ArtworkAddition.add(ownerPersistentID: owner.persistentID, sourceByteCount: 5000, trackCount: 2, in: paths,
                                        deviceFormats: [.init(formatID: 1027, width: 100, height: 100, pixelFormat: "L565")]) { w, h in
                try ITHMBImage(rendering: WriteTests.image(red: 1, green: 0, blue: 0), width: w, height: h)
            }
            library = library.linkingAlbumArtwork(album: "Aftermath", ownerPersistentID: owner.persistentID)
                .markingAlbumArtwork(album: "Aftermath", sourceByteCount: 5000)
        }
        var bytes = [UInt8](ITunesDBWriter.serialize(library))
        bytes[0x30] = 0; bytes[0x31] = 0
        try Data(bytes).write(to: paths.iTunesDB)
        for id in 10...16 {
            try Data(repeating: UInt8(id), count: 1000).write(to: paths.musicDirectory.appendingPathComponent("F00/\(id).mp3"))
        }

        let environment = LibraryEnvironment.isolated(in: root.appendingPathComponent("Support", isDirectory: true))
        let volume = try #require(IPodVolume.at(paths.mountPoint))
        var device = try IPodDevice.open(volume)
        device.usb = USBIdentity(productID: 0x1209)
        #expect(!device.supportsWriting, "an iPod Video is read-only by default")

        // The permission the way the app gives it: the switch on, then diagnostics.
        let permissions = ExperimentalPermissions(storage: .memory())
        permissions.isEnabled = true
        if policy == .developer {
            permissions.developerMode = true
        } else {
            try permissions.allow(device, diagnostics: Diagnostics.run(on: device, isMusicRunning: { false }))
        }
        let model = LibraryModel(environment: environment, permissions: permissions)
        await model.load(.device(device))
        #expect(model.state == .loaded)
        #expect(model.device?.writePolicy == policy)
        #expect(model.device?.writesOutsideConfirmedModels == true)
        return Rig(root: root, paths: paths, environment: environment, model: model)
    }

    @Test("an edit reaches the database unsigned, after a backup")
    func renameAlbum() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        let outcome = try await rig.model.apply()
        #expect(try rig.onDisk().tracks.contains { $0.album == "Currents (Deluxe)" })
        #expect(try DatabaseFormat.detect(header: Data(contentsOf: rig.paths.iTunesDB)).signing == .presumedUnsigned)
        #expect(!outcome.result.identicalToPrevious)
    }

    @Test("a removed file is copied to the Mac first, even without a folder chosen")
    func removalKeepsACopy() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let bends = try rig.album("The Bends")
        let bones = try #require(rig.model.tracks(of: bends).first { $0.title == "Bones" })
        try rig.model.deleteTrack(bones, in: bends)
        let outcome = try await rig.model.apply()

        #expect(outcome.deletedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: rig.musicFile(10).path))
        let archived = try FileManager.default.contentsOfDirectory(atPath: rig.environment.experimentalRemovalArchive.path)
        #expect(archived.count == 1)
        #expect(archived.first?.contains("Bones") == true)
    }

    @Test("developer mode removes without the forced copy, as on a confirmed model")
    func developerRemovesWithoutCopy() async throws {
        let rig = try await Self.rig(policy: .developer); defer { rig.cleanUp() }
        let bends = try rig.album("The Bends")
        let bones = try #require(rig.model.tracks(of: bends).first { $0.title == "Bones" })
        try rig.model.deleteTrack(bones, in: bends)
        _ = try await rig.model.apply()
        #expect(!FileManager.default.fileExists(atPath: rig.environment.experimentalRemovalArchive.path))
    }

    @Test("the repairs on every write are skipped: only the user's change goes in")
    func noRepairs() async throws {
        let rig = try await Self.rig(brokenMarker: 12); defer { rig.cleanUp() }
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        let outcome = try await rig.model.apply()
        #expect(outcome.repairs.artworkMarkers == 0)
        #expect(!(try #require(try rig.onDisk().tracks.first { $0.uniqueID == 12 }).hasArtworkMarker),
                "the zeroed marker stays as it was")
    }

    /// Found in a hardware test: an album added with artwork showed none on the iPod - the
    /// pointer at 0x160 is set by the write-time steps, and those were all off.
    @Test("an album's first artwork on an experimental iPod: its songs point to the image; other albums untouched")
    func firstCoverIsPointedTo() async throws {
        let rig = try await Self.rig(brokenMarker: 12, cover: true); defer { rig.cleanUp() }
        let currents = try rig.album("Currents")
        try rig.model.setArtwork(for: currents, image: try WriteTests.image(red: 0, green: 0, blue: 1), sourceByteCount: 7000)
        let outcome = try await rig.model.apply()
        #expect(outcome.coversWritten == 1)

        let artwork = try #require(try ArtworkDBParser.parse(Data(contentsOf: rig.paths.artworkDB)))
        let identifiers = Set(artwork.images.map(\.id))
        let written = try rig.onDisk().tracks
        let songs = written.filter { $0.album == "Currents" }
        #expect(!songs.isEmpty)
        #expect(songs.allSatisfy { identifiers.contains($0.artworkIdentifier) }, "every song points (0x160) to an existing image")
        #expect(!(try #require(written.first { $0.uniqueID == 12 }).hasArtworkMarker),
                "a repair outside the changed album still doesn't happen")
        #expect(written.filter { $0.album == "Aftermath" }.allSatisfy { $0.artworkIdentifier == 0 },
                "Aftermath wasn't changed: its missing pointer stays for the user to see, not for a rule from another model")
    }

    @Test("replacing the artwork of an album whose songs lack the pointer: the pointers come with it")
    func replacedCoverIsPointedTo() async throws {
        let rig = try await Self.rig(cover: true); defer { rig.cleanUp() }
        #expect(try rig.onDisk().tracks.filter { $0.album == "Aftermath" }.allSatisfy { $0.artworkIdentifier == 0 })
        try rig.model.setArtwork(for: try rig.album("Aftermath"), image: try WriteTests.image(red: 0, green: 1, blue: 0), sourceByteCount: 6000)
        _ = try await rig.model.apply()
        let identifiers = Set(try #require(try ArtworkDBParser.parse(Data(contentsOf: rig.paths.artworkDB))).images.map(\.id))
        #expect(try rig.onDisk().tracks.filter { $0.album == "Aftermath" }.allSatisfy { identifiers.contains($0.artworkIdentifier) })
    }

    @Test("adding needs a record of the same kind on this iPod: no cross-kind template")
    func sameKindTemplateOnly() throws {
        let library = try ITunesDBParser.parse(SyntheticLibrary.database()).mappingTracks { $0.settingFileKind(.mp3) }
        let device = IPodDevice(volume: IPodVolume(paths: IPodPaths(mountPoint: URL(fileURLWithPath: "/tmp/none")), name: "iPod",
                                                   totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                                fireWireID: nil,
                                format: DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: .presumedUnsigned),
                                model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly),
                                usb: USBIdentity(productID: 0x1209), writePolicy: .experimental)
        let rules = TrackAdditionRunner.AdditionRules(for: device)
        #expect(!rules.crossKindTemplates)
        #expect(!rules.unverifiedArtworkFormats)
        // Apple Lossless is the one kind with a profile measured on the Classic; this iPod has only MP3.
        let draft = TrackDraft(title: "New", album: "Currents", kind: .appleLossless, relativePath: ":iPod_Control:Music:F00:NEW.m4a")
        #expect(throws: TrackInsertionError.self) {
            try library.addingTracks([draft], crossKindTemplates: rules.crossKindTemplates)
        }
        #expect(try library.addingTracks([draft]).tracks.count == library.tracks.count + 1, "a confirmed model may")
        var developer = device
        developer.writePolicy = .developer
        #expect(TrackAdditionRunner.AdditionRules(for: developer).crossKindTemplates)
        #expect(TrackAdditionRunner.AdditionRules(for: developer).unverifiedArtworkFormats)
    }

    @Test("the first experimental write: the question for the next connection, the backup pinned")
    func firstWriteRecorded() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        #expect(rig.model.experimentalWriteAwaitingAnswer == nil)
        _ = try rig.model.setAlbumField(try rig.album("Currents"), .title, to: "Currents (Deluxe)")
        let outcome = try await rig.model.apply()

        let record = try #require(rig.model.experimentalWriteAwaitingAnswer)
        #expect(record.changes == 1)
        let grant = try #require(rig.model.permissions.grants.first)
        #expect(grant.firstBackupID == outcome.result.snapshot.id)

        _ = try rig.model.setAlbumField(try rig.album("Currents (Deluxe)"), .title, to: "Currents")
        _ = try await rig.model.apply()
        #expect(rig.model.permissions.grants.first?.firstBackupID == grant.firstBackupID, "the first backup stays the first")

        rig.model.permissions.answer(true, for: grant.identity)
        #expect(rig.model.experimentalWriteAwaitingAnswer == nil)
        #expect(rig.model.permissions.grants.first?.lastAnswer == true)
    }

    @Test("revoking the permission loads the iPod again, read-only")
    func revoke() async throws {
        let rig = try await Self.rig(); defer { rig.cleanUp() }
        let identity = try #require(rig.model.device?.identity)
        await rig.model.revokeExperimentalWriting(identity: identity)
        #expect(rig.model.device?.writePolicy == .standard)
        #expect(!rig.model.isWritable)
    }
}
