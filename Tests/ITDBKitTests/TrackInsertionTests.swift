import Foundation
import Testing
@testable import ITDBKit

@Suite("Adding tracks")
struct TrackInsertionTests {

    static func draft(
        title: String = "New Song", album: String = "Currents", artist: String = "Tame Impala",
        number: UInt32 = 3, kind: TrackFileKind = .mp3, path: String = "iPod_Control/Music/F07/ZZZZ.mp3"
    ) -> TrackDraft {
        TrackDraft(title: title, artist: artist, albumArtist: artist, album: album,
                   trackNumber: number, durationMilliseconds: 180_000, sizeBytes: 5_000_000,
                   bitRate: 256, sampleRate: 44_100, kind: kind, relativePath: path)
    }

    @Test("an added track can be placed in the middle of an album - that is how dropping a file on the list works")
    func placedInsideAlbum() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([Self.draft(title: "Dropped", number: 2)])
        let added = try #require(after.tracks.last)
        #expect(try after.trackOrder(album: "Currents").contains { $0.uniqueID == added.uniqueID })

        var order = try after.trackOrder(album: "Currents").map(\.uniqueID)
        order.removeAll { $0 == added.uniqueID }
        order.insert(added.uniqueID, at: 1)
        let placed = try after.settingTrackOrder(album: "Currents", uniqueIDs: order)
        #expect(try placed.trackOrder(album: "Currents").map(\.title) == ["Let It Happen", "Dropped", "Eventually"])
    }

    @Test("a new track has its own identifier, its own file and a date added")
    func newRecord() throws {
        let library = try LibraryFixture.standard()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let after = try library.addingTracks([Self.draft()], now: now) { 0xDEAD_BEEF_CAFE_0001 }

        #expect(after.tracks.count == library.tracks.count + 1)
        let added = try #require(after.tracks.last)
        #expect(added.title == "New Song")
        #expect(added.uniqueID == library.tracks.map(\.uniqueID).max()! + 1)
        #expect(added.persistentID == 0xDEAD_BEEF_CAFE_0001)
        #expect(added.relativePath == "iPod_Control/Music/F07/ZZZZ.mp3")
        #expect(added.dateAdded == now)
        #expect(added.playCount == 0)
        #expect(added.sizeBytes == 5_000_000)
        #expect(added.sizeBytesSecondary == 5_000_000)
        #expect(added.sampleRate == 44_100)
        #expect(added.sampleRateFloat == 44_100)
    }

    @Test("the format is described in four places at once")
    func fileKindFields() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([Self.draft()])
        let added = try #require(after.tracks.last)

        #expect(added.fileKind == .mp3)
        #expect(added.fields[.fileType] == "MPEG audio file")
        #expect(Array(added.rawHeader[0x18..<0x1C]) == Array("MP3 ".utf8).reversed())
        #expect(added.rawHeader[0x1D] == 1)
        #expect(Array(added.rawHeader[0x148..<0x14C]) == [0, 0, 0, 0])
    }

    @Test("a lossless track gets the lossless flag and the M4A container")
    func losslessFields() throws {
        var tracks = LibraryFixture.tracks
        tracks.append(LibraryFixture.Track(id: 20, title: "Reference", album: "Currents",
                                           artist: "Tame Impala", number: 9, kind: .appleLossless))
        let data = LibraryFixture.database(tracks: tracks, albumOrder: [3, 1, 2, 0, 4, 5, 6, 7],
                                           jump: [(65, 0, 2), (66, 2, 3), (67, 5, 3)])
        let library = try ITunesDBParser.parse(data)
        let after = try library.addingTracks([Self.draft(kind: .appleLossless,
                                                         path: "iPod_Control/Music/F07/ZZZZ.m4a")])
        let added = try #require(after.tracks.last)

        #expect(added.fileKind == .appleLossless)
        #expect(Array(added.rawHeader[0x18..<0x1C]) == Array("M4A ".utf8).reversed())
        #expect(added.rawHeader[0x1D] == 0)
        #expect(added.rawHeader[0x14B] == 2)
    }

    @Test("the second copy of the persistent identifier goes together with the first")
    func persistentIDTwin() throws {
        // The Classic layout: the second copy in every track (the fixture has zeros).
        let library = try LibraryFixture.standard().mappingTracks { $0.restoringSecondaryPersistentID() }
        let after = try library.addingTracks([Self.draft()]) { 0x0102_0304_0506_0708 }
        let added = try #require(after.tracks.last)
        let twin = (0..<8).reduce(UInt64(0)) { $0 | UInt64(added.rawHeader[0xA8 + $1]) << (8 * UInt64($1)) }
        #expect(twin == added.persistentID)
        #expect(twin == 0x0102_0304_0506_0708)
    }

    @Test("a library without the second copy (nano 2G) - the new track does not get it either")
    func noTwinWhereDeviceHasNone() throws {
        let library = try LibraryFixture.standard().mappingTracks { track in
            var copy = track
            for i in 0..<8 { copy.rawHeader[0xA8 + i] = 0 }
            return copy
        }
        let after = try library.addingTracks([Self.draft()]) { 0x0102_0304_0506_0708 }
        let added = try #require(after.tracks.last)
        #expect(added.persistentID == 0x0102_0304_0506_0708)
        #expect(added.secondaryPersistentID == 0)
    }

    @Test("the template must be of the same kind")
    func templateMustMatchKind() throws {
        let library = try LibraryFixture.standard()   // MP3 only
        #expect(throws: TrackInsertionError.self) {
            _ = try library.addingTracks([Self.draft(kind: .wav, path: "iPod_Control/Music/F07/ZZZZ.wav")])
        }
    }

    @Test("an iPod without an ALAC track: a record from this iPod's MP3, switched by the measured profile")
    func crossKindTemplate() throws {
        let library = try LibraryFixture.standard()   // MP3 only, like a nano 2G after Finder
        let base = try #require(library.templateTrack(for: .mp3))
        let after = try library.addingTracks([Self.draft(kind: .appleLossless, path: "iPod_Control/Music/F07/ZZZZ.m4a")])
        let added = try #require(after.tracks.last)

        #expect(added.fileKind == .appleLossless)
        #expect(Array(added.rawHeader[0x18..<0x1C]) == Array("M4A ".utf8).reversed())
        #expect(added.rawHeader[0x1D] == 0)
        #expect(added.rawHeader[0x14B] == 2)
        for (offset, value) in TrackKindProfile.appleLossless.bytes {
            #expect(added.rawHeader[offset] == value, "byte 0x\(String(offset, radix: 16))")
        }
        // A device-dependent field stays from this iPod's record.
        #expect(Array(added.rawHeader[0x124..<0x12C]) == Array(base.rawHeader[0x124..<0x12C]))
    }

    @Test("a record of the same kind on the iPod wins over the profile")
    func sameKindBeatsProfile() throws {
        var tracks = LibraryFixture.tracks
        tracks.append(LibraryFixture.Track(id: 20, title: "Reference", album: "Currents",
                                           artist: "Tame Impala", number: 9, kind: .appleLossless))
        let data = LibraryFixture.database(tracks: tracks, albumOrder: [3, 1, 2, 0, 4, 5, 6, 7],
                                           jump: [(65, 0, 2), (66, 2, 3), (67, 5, 3)])
        let library = try ITunesDBParser.parse(data).mappingTracks { track in
            guard track.fileKind == .appleLossless else { return track }
            var copy = track
            copy.rawHeader[0x90] = 99   // a value the profile does not have
            return copy
        }
        let after = try library.addingTracks([Self.draft(kind: .appleLossless, path: "iPod_Control/Music/F07/ZZZZ.m4a")])
        #expect(try #require(after.tracks.last).rawHeader[0x90] == 99)
    }

    @Test("the template is the record with the fewest foreign values")
    func cleanestTemplateWins() throws {
        var library = try LibraryFixture.standard()
        // We dirty the first record in a field the generator does not overwrite.
        library = library.mappingTracks { track in
            guard track.uniqueID == 10 else { return track }
            var copy = track
            copy.rawHeader[0x0BC] = 0x7F
            return copy
        }
        let template = try #require(library.templateTrack(for: .mp3))
        #expect(template.uniqueID != 10)
    }

    @Test("all browse tables stay permutations, in both copies of the playlist")
    func tablesStayPermutations() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([Self.draft()])
        let count = after.tracks.count

        var checked = 0
        for section in after.sections {
            guard case .playlists(let playlists) = section.content else { continue }
            for playlist in playlists where playlist.isMaster {
                for mhod in playlist.mhods {
                    guard let index = BrowseIndex(mhod: mhod) else { continue }
                    #expect(index.isPermutation(of: count))
                    checked += 1
                }
                #expect(playlist.entries.count == count)
                #expect(playlist.entries.contains { $0.trackID == after.tracks.last!.uniqueID })
            }
        }
        #expect(checked == 2)   // one album table in each of the two sections
    }

    @Test("a new track goes into its album, not to the end of the table")
    func landsInsideItsAlbum() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([Self.draft(number: 3)])
        let index = try #require(after.browseIndex(.album))
        let tracks = after.tracks
        let albums = index.entries.map { tracks[Int($0)].album ?? "" }
        // The Currents tracks are next to each other, the new track among them.
        let currents = albums.enumerated().filter { $0.element == "Currents" }.map(\.offset)
        #expect(currents.count == 3)
        #expect(currents == Array(currents.first!...currents.last!))
        let titles = currents.map { tracks[Int(index.entries[$0])].title ?? "" }
        #expect(titles == ["Let It Happen", "Eventually", "New Song"])
    }

    @Test("the jump bar covers all positions after adding")
    func jumpTableCovers() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([Self.draft(album: "Zoo", artist: "Zebra",
                                                         path: "iPod_Control/Music/F07/YYYY.mp3")])
        let jump = try #require(after.jumpTable(.album))
        #expect(jump.entries.reduce(0) { $0 + Int($1.count) } == after.tracks.count)
        #expect(jump.lettersAreContiguous)
        #expect(jump.entries.last?.letter == UInt32(UInt8(ascii: "Z")))
        var running = 0
        for entry in jump.entries {
            #expect(Int(entry.start) == running)
            running += Int(entry.count)
        }
    }

    @Test("a track attached to an album inherits its sort fields")
    func inheritsSortFields() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([Self.draft(album: "The Bends", artist: "Radiohead",
                                                         number: 4)])
        let added = try #require(after.tracks.last)
        #expect(added.sortAlbum == "Bends")
        #expect(added.deviceGroupingKey == library.tracks.first { $0.album == "The Bends" }!.deviceGroupingKey)
    }

    @Test("a new album gets its own record in the album list")
    func newAlbumRecord() throws {
        let library = try LibraryFixture.standard()
        let before = library.albums.count
        let after = try library.addingTracks([Self.draft(album: "Loveless", artist: "My Bloody Valentine",
                                                         path: "iPod_Control/Music/F07/XXXX.mp3")])
        #expect(after.albums.count == before + 1)
        if let album = after.albums.last {
            #expect(album.title == "Loveless")
            #expect(album.artworkOwnerPersistentID == 0)
            #expect(UInt32(album.index) == after.tracks.last?.albumRecordIndex)
        }
    }

    @Test("the same path cannot go into the database twice")
    func duplicatePathRefused() throws {
        let library = try LibraryFixture.standard()
        let once = try library.addingTracks([Self.draft()])
        #expect(throws: TrackInsertionError.self) {
            _ = try once.addingTracks([Self.draft()])
        }
    }

    @Test("a track without a title is rejected")
    func emptyTitleRefused() throws {
        let library = try LibraryFixture.standard()
        #expect(throws: TrackInsertionError.self) {
            _ = try library.addingTracks([Self.draft(title: "   ")])
        }
    }

    @Test("the database after adding can be written and read without loss")
    func roundTrip() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([
            Self.draft(),
            Self.draft(title: "Second", album: "Aftermath", artist: "Rolling Stones",
                       number: 3, path: "iPod_Control/Music/F08/WWWW.mp3"),
        ])
        let reparsed = try ITunesDBParser.parse(ITunesDBWriter.serialize(after))

        #expect(reparsed.tracks.count == after.tracks.count)
        #expect(reparsed.tracks.map(\.uniqueID) == after.tracks.map(\.uniqueID))
        #expect(reparsed.tracks.map(\.title) == after.tracks.map(\.title))
        #expect(reparsed.tracks.map(\.relativePath) == after.tracks.map(\.relativePath))
        #expect(reparsed.albums.count == after.albums.count)
        let index = try #require(reparsed.browseIndex(.album))
        #expect(index.isPermutation(of: reparsed.tracks.count))
        // Reading again must give the same byte-for-byte write.
        #expect(ITunesDBWriter.serialize(reparsed) == ITunesDBWriter.serialize(after))
    }
}

@Suite("Insertion point in the table")
struct InsertionPositionTests {

    /// The table on a real device starts with UTOPIA, and only then comes
    /// the alphabet. The rule "before the first greater one" therefore threw every
    /// new album to position zero.
    @Test("one entry out of place does not drag a new album to the start")
    func strayLeadingEntryIgnored() throws {
        let library = try LibraryFixture.standard()
        // Currents (index 5 and 6) to the start of the table - like UTOPIA on the iPod.
        let strayOrder: [UInt32] = [5, 6, 3, 1, 2, 0, 4]
        let data = LibraryFixture.database(tracks: LibraryFixture.tracks, albumOrder: strayOrder,
                                           jump: [(67, 0, 2), (65, 2, 2), (66, 4, 3)])
        let stray = try ITunesDBParser.parse(data)
        _ = library

        // "Bagpipes" falls between "Aftermath" and "Bends" (sortAlbum without "The").
        let after = try stray.addingTracks([TrackInsertionTests.draft(
            title: "Reel", album: "Bagpipes", artist: "Can", number: 1,
            path: "iPod_Control/Music/F07/BBBB.mp3")])
        let index = try #require(after.browseIndex(.album))
        let tracks = after.tracks
        let albums = index.entries.map { tracks[Int($0)].album ?? "" }

        #expect(albums.first != "Bagpipes")
        let position = try #require(albums.firstIndex(of: "Bagpipes"))
        #expect(albums[position - 1] == "Aftermath")
        #expect(albums[position + 1] == "The Bends")
    }

    @Test("an album that falls at the end goes to the end")
    func lastStaysLast() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([TrackInsertionTests.draft(
            title: "Zulu", album: "Zoo", artist: "Zebra", number: 1,
            path: "iPod_Control/Music/F07/ZZZZ.mp3")])
        let index = try #require(after.browseIndex(.album))
        let tracks = after.tracks
        #expect(tracks[Int(index.entries.last!)].album == "Zoo")
    }

    @Test("an album that falls at the start goes to the start")
    func firstStaysFirst() throws {
        let library = try LibraryFixture.standard()
        let after = try library.addingTracks([TrackInsertionTests.draft(
            title: "Aaa", album: "Abbey Road", artist: "The Beatles", number: 1,
            path: "iPod_Control/Music/F07/AAAA.mp3")])
        let index = try #require(after.browseIndex(.album))
        let tracks = after.tracks
        #expect(tracks[Int(index.entries.first!)].album == "Abbey Road")
    }
}
