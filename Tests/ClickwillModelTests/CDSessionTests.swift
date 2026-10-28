import Foundation
import Testing
@testable import ClickwillModel

/// A disc in the drive without a drive, a network or AppKit: lookup, artwork, a pasted
/// list, the format memory, ripping and the disc list - on `CDServices` fakes.
@Suite("Disc: session and disc list")
@MainActor
struct CDSessionTests {

    /// A session the lookup fake can change during the query -
    /// like a user who clicks before the server answers.
    @MainActor final class Holder { var session: CDSession? }

    final class Saved: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func append(_ value: String) { lock.withLock { values.append(value) } }
        var all: [String] { lock.withLock { values } }
    }

    nonisolated static func release(_ id: String, title: String, songs: Int = 12) -> CDRelease {
        CDRelease(id: id, title: title, artist: "Ozzy Osbourne", year: 1995, pressingYear: 1995, country: "US",
                  label: "Epic", discNumber: 1, totalDiscs: 1, isCompilation: false, hasFrontCover: true,
                  tracks: (1...songs).map { CDRelease.Track(number: $0, title: "\(title) \($0)", artist: "Ozzy Osbourne",
                                                             durationMilliseconds: nil) })
    }

    static func services(lookup: CDServices.Lookup = .init(releases: { _ in [] }, frontCover: { _ in nil }),
                         mounted: @escaping @Sendable () -> [AudioCD] = { [] },
                         ejected: Saved = Saved(), saved: Saved = Saved(),
                         stored: CDRipper.Format? = nil, root: URL? = nil) -> CDServices {
        CDServices(drive: .init(mounted: mounted, eject: { ejected.append($0.path) }),
                   lookup: lookup,
                   ripping: .init(root: root ?? FileManager.default.temporaryDirectory.appendingPathComponent("cd-unused")),
                   formatMemory: .init(load: { stored }, save: { saved.append($0.rawValue) }))
    }

    @Test("lookup: releases, names from the first one, artwork a moment later")
    func lookUpFound() async {
        let cover = Data([1, 2, 3])
        let services = Self.services(lookup: .init(
            releases: { _ in [Self.release("a", title: "Ozzmosis"), Self.release("b", title: "Ozzmosis (Japan)")] },
            frontCover: { $0.id == "a" ? cover : nil }))
        let session = CDSession(disc: AudioCDTests.ozzmosis, services: services)
        #expect(session.needsLookUp)

        await session.lookUp()
        #expect(session.lookup == .found)
        #expect(!session.needsLookUp)
        #expect(session.releases.map(\.id) == ["a", "b"])
        #expect(session.selectedRelease?.id == "a")
        #expect(session.draft.album == "Ozzmosis")
        #expect(session.draft.songs[0].title == "Ozzmosis 1")
        #expect(session.draft.cover == cover)
        #expect(session.title == "Ozzmosis")

        await session.choose(session.releases[1])
        #expect(session.draft.album == "Ozzmosis (Japan)")
        #expect(session.draft.cover == nil, "the second release has no artwork")
    }

    @Test("lookup: the disc is not in the database, the server refused, no network")
    func lookUpOutcomes() async {
        let empty = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services())
        await empty.lookUp()
        #expect(empty.lookup == .notFound)
        #expect(!empty.needsLookUp)
        #expect(empty.title == "Audio CD")

        let busy = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services(lookup: .init(
            releases: { _ in throw MusicBrainz.LookupError.busy }, frontCover: { _ in nil })))
        await busy.lookUp()
        #expect(busy.lookup == .failed(.badAnswer(.busy)))
        #expect(busy.needsLookUp, "after an error the lookup is the next step again")

        let offline = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services(lookup: .init(
            releases: { _ in throw URLError(.notConnectedToInternet) }, frontCover: { _ in nil })))
        await offline.lookUp()
        #expect(offline.lookup == .failed(.unreachable))
    }

    @Test("late artwork: does not overwrite our own artwork or another release")
    func lateCover() async {
        let holder = Holder()
        let mine = Data([9])
        let services = Self.services(lookup: .init(releases: { _ in [] }, frontCover: { release in
            await MainActor.run {
                // During the query the user chose their own artwork or another release.
                if release.id == "a" { holder.session?.draft.cover = mine }
                if release.id == "b" { holder.session?.draft.apply(Self.release("c", title: "Other")) }
            }
            return Data([1])
        }))
        let session = CDSession(disc: AudioCDTests.ozzmosis, services: services)
        holder.session = session

        await session.choose(Self.release("a", title: "Ozzmosis"))
        #expect(session.draft.cover == mine)

        await session.choose(Self.release("b", title: "Ozzmosis"))
        #expect(session.draft.releaseID == "c")
        #expect(session.draft.cover == nil)
    }

    @Test("demo recording: a saved response and artwork instead of the network")
    func recordedLookup() async throws {
        let disc = AudioCDTests.ozzmosis
        let tracks = (1...12).map { #"{"position":\#($0),"title":"Song \#($0)","length":1000}"# }.joined(separator: ",")
        let json = #"{"releases":[{"id":"rel-1","title":"Ozzmosis","date":"1995","artist-credit":[{"name":"Ozzy Osbourne","joinphrase":""}],"media":[{"position":1,"track-count":12,"discs":[{"id":"\#(disc.discID)"}],"tracks":[\#(tracks)]}]}]}"#
        let cover = AudioCDTests.tinyJPEG()
        let session = CDSession(disc: disc, services: Self.services(lookup: .recorded(response: Data(json.utf8), cover: cover)))
        await session.lookUp()
        #expect(session.lookup == .found)
        #expect(session.draft.album == "Ozzmosis")
        #expect(session.draft.songs[11].title == "Song 12")
        #expect(session.draft.cover == cover)

        let broken = CDSession(disc: disc, services: Self.services(lookup: .recorded(response: Data("{".utf8), cover: nil)))
        await broken.lookUp()
        #expect(broken.lookup != .found, "a broken recording does not reach the network")
    }

    @Test("a result given up front: the state after the lookup without waiting")
    func showFound() {
        let session = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services())
        session.showFound([], cover: nil)
        #expect(session.lookup == .idle)
        session.showFound([Self.release("a", title: "Ozzmosis")], cover: Data([7]))
        #expect(session.lookup == .found)
        #expect(session.draft.album == "Ozzmosis")
        #expect(session.draft.cover == Data([7]))
    }

    @Test("a pasted list: it matches, empty, a different number of songs - the draft unchanged")
    func paste() {
        let session = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services())
        #expect(session.pasteTrackList("") == .noTrackList)
        #expect(session.pasteTrackList("1. Perry Mason\n2. I Just Want You") == .countMismatch(lines: 2, songs: 12))
        #expect(session.draft.songs[0].title == "Track 1")
        #expect(session.pasteTrackList((1...12).map { "\($0). Song \($0)" }.joined(separator: "\n")) == .filled)
        #expect(session.draft.songs[11].title == "Song 12")
    }

    @Test("format: starts from the remembered one, a change goes into the memory")
    func formatMemory() {
        let saved = Saved()
        #expect(CDSession(disc: AudioCDTests.ozzmosis, services: Self.services()).format == .appleLossless)
        let session = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services(saved: saved, stored: .aac256))
        #expect(session.format == .aac256)
        #expect(saved.all.isEmpty)
        session.format = .aac128
        #expect(saved.all == ["aac128"])
    }

    @Test("artwork from a file: an image yes, another file no")
    func coverFromFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cd-cover-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = folder.appendingPathComponent("notes.jpg")
        try Data("not an image".utf8).write(to: text)
        let image = folder.appendingPathComponent("cover.jpg")
        try AudioCDTests.tinyJPEG().write(to: image)

        let session = CDSession(disc: AudioCDTests.ozzmosis, services: Self.services())
        #expect(!session.setCover(from: text))
        #expect(session.draft.cover == nil)
        #expect(!session.setCover(from: folder.appendingPathComponent("missing.jpg")))
        #expect(session.setCover(from: image))
        #expect(session.draft.cover == AudioCDTests.tinyJPEG())
    }

    /// A folder pretending to be a disc: a `.TOC.plist` table and one-second AIFF files.
    static func fixtureDisc(in folder: URL, tracks: Int) throws -> AudioCD {
        let disc = folder.appendingPathComponent("Audio CD")
        try FileManager.default.createDirectory(at: disc, withIntermediateDirectories: true)
        let entries = (1...tracks).map { (point: $0, start: 150 + ($0 - 1) * 75, data: false) }
        try AudioCDTests.toc(sessions: [(1, 150 + tracks * 75, entries)]).write(to: disc.appendingPathComponent(".TOC.plist"))
        for number in 1...tracks {
            try AudioCDTests.writeSilence(to: disc.appendingPathComponent("\(number) Audio Track.aiff"), seconds: 1)
        }
        return try AudioCD(volume: disc)
    }

    @Test("ripping: the checked songs to the folder from the services, the files for the requester")
    func rip() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cd-session-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let disc = try Self.fixtureDisc(in: folder, tracks: 3)
        let root = folder.appendingPathComponent("Music")
        let session = CDSession(disc: disc, services: Self.services(root: root))
        session.draft.album = "Silence"
        session.draft.albumArtist = "Nobody"
        session.draft.songs[1].included = false

        let files: [URL] = await withCheckedContinuation { done in
            session.rip { done.resume(returning: $0) }
            #expect(session.isRipping)
            #expect(session.ripping == CDSession.RipProgress(index: 0, fraction: 0))
        }
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.path.hasPrefix(root.path) })
        #expect(!session.isRipping)
        #expect(session.ripping == nil)
        #expect(session.outcome?.files == files)
        #expect(session.outcome?.failed.isEmpty == true)
        // Progress comes in separate tasks - the last ones may arrive after `done`.
        for _ in 0..<50 where session.ripped.count < 2 { await Task.yield() }
        #expect(session.ripped == [1, 3])
    }

    @Test("ejecting stops ripping and ejects this volume")
    func eject() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cd-eject-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let disc = try Self.fixtureDisc(in: folder, tracks: 1)
        let ejected = Saved()
        let session = CDSession(disc: disc, services: Self.services(ejected: ejected, root: folder.appendingPathComponent("Music")))
        session.rip { _ in Issue.record("an interrupted rip does not hand over files") }
        session.eject()
        #expect(!session.isRipping)
        for _ in 0..<200 where ejected.all.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(ejected.all == [disc.volume.path])
    }

    @Test("the disc list: a new disc gets a session, an ejected one loses it, a fake replaces the drive")
    func store() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cd-store-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let disc = try Self.fixtureDisc(in: folder, tracks: 1)
        final class Drive: @unchecked Sendable { var discs: [AudioCD] = [] }
        let drive = Drive()
        let store = AudioCDStore(services: Self.services(mounted: { drive.discs }))

        #expect(store.refresh().isEmpty)
        drive.discs = [AudioCDTests.ozzmosis]
        #expect(store.refresh().map(\.volume) == [AudioCDTests.ozzmosis.volume])
        let session = try #require(store.session(AudioCDTests.ozzmosis.volume))
        #expect(store.refresh().isEmpty, "the same disc - nothing new")
        #expect(store.session(AudioCDTests.ozzmosis.volume) === session, "the session stays between refreshes")

        drive.discs = []
        store.refresh()
        #expect(store.discs.isEmpty)
        #expect(store.session(AudioCDTests.ozzmosis.volume) == nil)

        drive.discs = [AudioCDTests.ozzmosis]
        store.refresh()
        let fixture = try #require(store.add(fixture: disc.volume))
        #expect(store.discs.map(\.volume) == [fixture.volume])
        #expect(store.session(fixture.volume) != nil)
        #expect(store.add(fixture: folder) == nil, "a folder without a table is not a disc")
    }
}
