import Foundation
import Testing
@testable import ITDBKit

/// Assembles a synthetic database, to test the parser without a user's private library.
private struct DatabaseBuilder {
    static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
    static func u16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    static func u64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> (8 * $0)) & 0xFF) } }

    /// A text mhod: 24 B of header, then position, length, encoding, a reserve and UTF-16LE.
    static func textMhod(type: UInt32, _ text: String) -> [UInt8] {
        var body = u32(1) + u32(UInt32(text.utf16.count * 2)) + u32(1) + u32(0)
        for unit in text.utf16 { body += u16(unit) }
        let total = 24 + body.count
        var header = Array("mhod".utf8) + u32(24) + u32(UInt32(total)) + u32(type)
        header += [UInt8](repeating: 0, count: 24 - header.count)
        return header + body
    }

    /// A container with the given signature and header length, with fields inserted at offsets.
    static func container(
        _ signature: String, headerLength: Int, fields: [Int: [UInt8]], children: [UInt8]
    ) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: headerLength)
        for (index, byte) in Array(signature.utf8).enumerated() { header[index] = byte }
        for (index, byte) in u32(UInt32(headerLength)).enumerated() { header[4 + index] = byte }
        for (index, byte) in u32(UInt32(headerLength + children.count)).enumerated() { header[8 + index] = byte }
        for (offset, value) in fields {
            for (index, byte) in value.enumerated() { header[offset + index] = byte }
        }
        return header + children
    }

    static func list(_ signature: String, headerLength: Int, count: Int) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: headerLength)
        for (index, byte) in Array(signature.utf8).enumerated() { header[index] = byte }
        for (index, byte) in u32(UInt32(headerLength)).enumerated() { header[4 + index] = byte }
        for (index, byte) in u32(UInt32(count)).enumerated() { header[8 + index] = byte }
        return header
    }

    /// An album with three tracks, one of which has an outlying sort field -
    /// it reproduces the case that splits an album into two covers.
    static func threeTrackAlbum() -> Data {
        var tracks: [UInt8] = []
        let rows: [(String, UInt32, String)] = [
            ("First", 1, "Weeknd"), ("Second", 2, "Weeknd"), ("Third", 3, "The Weeknd"),
        ]
        for (title, number, sortArtist) in rows {
            let mhods = textMhod(type: 1, title)
                + textMhod(type: 3, "Hurry Up Tomorrow")
                + textMhod(type: 4, "The Weeknd")
                + textMhod(type: 23, sortArtist)
            tracks += container("mhit", headerLength: 624, fields: [
                0x0C: u32(4), 0x10: u32(100 + number), 0x2C: u32(number),
            ], children: mhods)
        }
        let list = self.list("mhlt", headerLength: 92, count: rows.count) + tracks
        let section = container("mhsd", headerLength: 96, fields: [0x0C: u32(1)], children: list)

        var header = [UInt8](repeating: 0, count: 244)
        for (index, byte) in Array("mhbd".utf8).enumerated() { header[index] = byte }
        for (index, byte) in u32(244).enumerated() { header[4 + index] = byte }
        for (index, byte) in u32(UInt32(244 + section.count)).enumerated() { header[8 + index] = byte }
        for (index, byte) in u32(1).enumerated() { header[0x14 + index] = byte }
        for (index, byte) in u16(1).enumerated() { header[0x30 + index] = byte }
        return Data(header + section)
    }

    /// A database with one track: mhbd -> mhsd(type 1) -> mhlt -> mhit -> mhod.
    static func oneTrackDatabase() -> Data {
        let mhods = textMhod(type: 1, "Another Track")
            + textMhod(type: 3, "A Great Chaos")
            + textMhod(type: 4, "Ken Carson")
            + textMhod(type: 28, "Great Chaos")
            + textMhod(type: 2, ":iPod_Control:Music:F24:VQGB.mp3")

        let track = container("mhit", headerLength: 624, fields: [
            0x0C: u32(5),          // number of mhods
            0x10: u32(579),        // unique id
            0x24: u32(1_860_948),  // size
            0x28: u32(154_462),    // length in ms
            0x2C: u32(14),         // track number
            0x30: u32(20),         // total tracks
            0x34: u32(2023),       // year
            0x38: u32(320),        // bitrate
            0x3C: u32(44_100 << 16),
            0x50: u32(7),          // plays
            0x5C: u32(1),          // disc number
            0x60: u32(1),          // total discs
            0x70: u64(0xDEAD_BEEF_1234_5678),
        ], children: mhods)

        let listAndTrack = list("mhlt", headerLength: 92, count: 1) + track
        let section = container("mhsd", headerLength: 96, fields: [0x0C: u32(1)], children: listAndTrack)

        var header = [UInt8](repeating: 0, count: 244)
        for (index, byte) in Array("mhbd".utf8).enumerated() { header[index] = byte }
        for (index, byte) in u32(244).enumerated() { header[4 + index] = byte }
        for (index, byte) in u32(UInt32(244 + section.count)).enumerated() { header[8 + index] = byte }
        for (index, byte) in u32(117).enumerated() { header[0x10 + index] = byte }
        for (index, byte) in u32(1).enumerated() { header[0x14 + index] = byte }
        for (index, byte) in u64(0x1122_3344_5566_7788).enumerated() { header[0x18 + index] = byte }
        for (index, byte) in u16(1).enumerated() { header[0x30 + index] = byte }
        return Data(header + section)
    }
}

@Suite("ByteReader")
struct ByteReaderTests {
    @Test("reads little-endian")
    func littleEndian() throws {
        let reader = ByteReader(Data([0x78, 0x56, 0x34, 0x12, 0xEF, 0xBE, 0xAD, 0xDE]))
        #expect(try reader.u16(at: 0) == 0x5678)
        #expect(try reader.u32(at: 0) == 0x1234_5678)
        #expect(try reader.u64(at: 0) == 0xDEAD_BEEF_1234_5678)
    }

    @Test("refuses to read past the end")
    func bounds() {
        let reader = ByteReader(Data([0x01, 0x02]))
        #expect(throws: ITDBError.self) { try reader.u32(at: 0) }
        #expect(throws: ITDBError.self) { try reader.u16(at: 1) }
    }

    @Test("decodes UTF-16LE")
    func utf16() throws {
        let reader = ByteReader(Data([0x41, 0x00, 0x142, 0x01].map { UInt8($0 & 0xFF) }))
        #expect(try reader.utf16String(at: 0, byteCount: 2) == "A")
    }
}

@Suite("time and paths")
struct ConversionTests {
    @Test("the Mac epoch starts in 1904")
    func macEpoch() {
        let date = MacTime.date(from: 3_861_691_370)
        #expect(date != nil)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date!
        )
        #expect(components.year == 2026)
        #expect(MacTime.date(from: 0) == nil)
        #expect(MacTime.value(from: nil) == 0)
        #expect(MacTime.value(from: date) == 3_861_691_370)
    }

    @Test("a path from the database turns into a volume path and back")
    func paths() {
        let location = ":iPod_Control:Music:F03:UOLJ.m4a"
        let path = ITTrack.filesystemPath(fromDatabaseLocation: location)
        #expect(path == "iPod_Control/Music/F03/UOLJ.m4a")
        #expect(ITTrack.databaseLocation(fromFilesystemPath: path) == location)
    }

    @Test("text and binary types are told apart")
    func mhodKinds() {
        #expect(MhodType.title.carriesText)
        #expect(MhodType.sortAlbum.carriesText)
        #expect(MhodType.albumTitle.carriesText)
        #expect(!MhodType.playlistEntryData.carriesText)
        #expect(!MhodType.smartPlaylistRules.carriesText)
        // An unknown type is not an error - it passes through the model unchanged.
        #expect(MhodType(rawValue: 999).carriesText)
        #expect(MhodType(rawValue: 999).label == "type 999")
    }
}

@Suite("iTunesDB parser")
struct ParserTests {
    @Test("reads a synthetic database with one track")
    func parsesSyntheticDatabase() throws {
        let library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())

        #expect(library.version == 117)
        #expect(library.hashingScheme == 1)
        #expect(library.databaseID == 0x1122_3344_5566_7788)
        #expect(library.sections.count == 1)
        #expect(library.tracks.count == 1)

        let track = try #require(library.tracks.first)
        #expect(track.uniqueID == 579)
        #expect(track.title == "Another Track")
        #expect(track.album == "A Great Chaos")
        #expect(track.artist == "Ken Carson")
        #expect(track.sortAlbum == "Great Chaos")
        #expect(track.trackNumber == 14)
        #expect(track.totalTracks == 20)
        #expect(track.year == 2023)
        #expect(track.bitRate == 320)
        #expect(track.sampleRate == 44_100)
        #expect(track.playCount == 7)
        #expect(track.discNumber == 1)
        #expect(track.durationMilliseconds == 154_462)
        #expect(track.persistentID == 0xDEAD_BEEF_1234_5678)
        #expect(track.relativePath == "iPod_Control/Music/F24/VQGB.mp3")
        #expect(track.effectiveAlbumArtist == "Ken Carson")
        #expect(track.mhods.count == 5)
    }

    @Test("keeps the original bytes of every record")
    func preservesRawBytes() throws {
        let data = DatabaseBuilder.oneTrackDatabase()
        let library = try ITunesDBParser.parse(data)
        let track = try #require(library.tracks.first)

        #expect(library.rawHeader.count == 244)
        #expect(track.rawHeader.count == 624)
        #expect(Array(track.rawHeader.prefix(4)) == Array("mhit".utf8))
        for mhod in track.mhods {
            #expect(mhod.rawHeader.count == 24)
            #expect(Array(mhod.rawHeader.prefix(4)) == Array("mhod".utf8))
        }
        #expect(library.sourceByteCount == data.count)
    }

    @Test("rejects a database with a mismatched declared length")
    func rejectsTruncated() {
        var bytes = [UInt8](DatabaseBuilder.oneTrackDatabase())
        bytes.removeLast(10)
        #expect(throws: ITDBError.self) { try ITunesDBParser.parse(Data(bytes)) }
        #expect(throws: ITDBError.self) { try ITunesDBParser.parse(Data(repeating: 0x41, count: 400)) }
    }

    @Test("groups tracks into albums by name and artist")
    func groupsAlbums() throws {
        let library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        let groups = library.albumGroups()
        #expect(groups.count == 1)
        let key = try #require(groups.keys.first)
        #expect(key.album == "A Great Chaos")
        #expect(key.albumArtist == "Ken Carson")
    }
}

@Suite("artwork")
struct ArtworkTests {
    /// Regression: the product 31 * 255 does not fit in UInt8 and broke the decoder.
    @Test("the decoder does not overflow on extreme colors")
    func decoderHandlesExtremes() {
        let white: [UInt8] = [0xFF, 0xFF]
        let black: [UInt8] = [0x00, 0x00]
        let red: [UInt8] = [0x00, 0xF8]      // 0xF800 = full red
        let raw = white + black + red + black

        let image = ITHMB.decodeRGB565(raw, width: 2, height: 2, pixelStride: 2)
        #expect(image.width == 2 && image.height == 2)
        #expect(Array(image.rgba.prefix(4)) == [255, 255, 255, 255])
        #expect(Array(image.rgba[4..<8]) == [0, 0, 0, 255])
        #expect(Array(image.rgba[8..<12]) == [255, 0, 0, 255])
    }

    @Test("a row stride larger than the width does not shift the image")
    func honoursStride() {
        // A 2x2 image in a slot with a 3-pixel stride - the third pixel of each row is padding.
        var raw = [UInt8]()
        for row in 0..<2 {
            raw += row == 0 ? [0x00, 0xF8, 0xE0, 0x07] : [0x1F, 0x00, 0xFF, 0xFF]
            raw += [0xAA, 0xAA]   // padding that must be ignored
        }
        let image = ITHMB.decodeRGB565(raw, width: 2, height: 2, pixelStride: 3)
        #expect(Array(image.rgba.prefix(4)) == [255, 0, 0, 255])       // red
        #expect(Array(image.rgba[4..<8]) == [0, 255, 0, 255])          // green
        #expect(Array(image.rgba[8..<12]) == [0, 0, 255, 255])         // blue
        #expect(Array(image.rgba[12..<16]) == [255, 255, 255, 255])    // white
    }

    @Test("encoding and decoding round-trip")
    func roundTrip() {
        let original = ITHMBImage(
            width: 2, height: 2,
            rgba: [255, 0, 0, 255,  0, 255, 0, 255,  0, 0, 255, 255,  255, 255, 255, 255]
        )
        let encoded = ITHMB.encodeRGB565(original, pixelStride: 3, slotSize: 12)
        #expect(encoded.count == 12)
        let decoded = ITHMB.decodeRGB565(encoded, width: 2, height: 2, pixelStride: 3)
        #expect(decoded.rgba == original.rgba)
    }

    @Test("a variant computes the row stride from the slot")
    func strideFromSlot() {
        // Format 1061 keeps a 55x55 image in a 6160 B slot, which gives a 56-pixel stride.
        let variant = ArtworkVariant(
            correlationID: 1061, fileName: ":F1061_1.ithmb",
            byteOffset: 0, byteCount: 6160, width: 55, height: 55
        )
        #expect(variant.pixelStride == 56)
        #expect(variant.plainFileName == "F1061_1.ithmb")

        let exact = ArtworkVariant(
            correlationID: 1060, fileName: ":F1060_1.ithmb",
            byteOffset: 0, byteCount: 204_800, width: 320, height: 320
        )
        #expect(exact.pixelStride == 320)
    }
}

@Suite("writer")
struct WriterTests {

    @Test("reproduces the database byte for byte")
    func roundTrip() throws {
        let original = DatabaseBuilder.oneTrackDatabase()
        let library = try ITunesDBParser.parse(original)
        let rebuilt = ITunesDBWriter.serialize(library)
        #expect(rebuilt.count == original.count)
        #expect(rebuilt == original)
    }

    @Test("a reproduced database parses into the same thing")
    func reparses() throws {
        let library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        let again = try ITunesDBParser.parse(ITunesDBWriter.serialize(library))

        #expect(again.tracks.count == library.tracks.count)
        #expect(again.version == library.version)
        #expect(again.databaseID == library.databaseID)
        let before = try #require(library.tracks.first)
        let after = try #require(again.tracks.first)
        #expect(after.uniqueID == before.uniqueID)
        #expect(after.title == before.title)
        #expect(after.sortAlbum == before.sortAlbum)
        #expect(after.persistentID == before.persistentID)
        #expect(after.trackNumber == before.trackNumber)
    }

    @Test("a field change reaches the bytes and comes back on reading")
    func fieldEditsSurvive() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        guard case .tracks(var tracks) = library.sections[0].content else {
            Issue.record("the first section should contain tracks")
            return
        }
        tracks[0].trackNumber = 3
        tracks[0].discNumber = 2
        tracks[0].year = 1999
        tracks[0].playCount = 42
        tracks[0].rating = 80
        library.sections[0].content = .tracks(tracks)

        let reparsed = try ITunesDBParser.parse(ITunesDBWriter.serialize(library))
        let track = try #require(reparsed.tracks.first)
        #expect(track.trackNumber == 3)
        #expect(track.discNumber == 2)
        #expect(track.year == 1999)
        #expect(track.playCount == 42)
        #expect(track.rating == 80)
        // the rest of the record must stay untouched
        #expect(track.title == "Another Track")
        #expect(track.persistentID == 0xDEAD_BEEF_1234_5678)
        #expect(track.sizeBytes == 1_860_948)
    }

    @Test("a signed database verifies with the device key")
    func signedOutputVerifies() throws {
        let library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        let fireWireID = try Hash58.fireWireID(fromHex: "000A27001234ABCD")
        let signed = try Hash58.sign(ITunesDBWriter.serialize(library), fireWireID: fireWireID)

        #expect(try Hash58.verify(database: signed, fireWireID: fireWireID).matches)
        #expect(try Hash58.hashingScheme(in: signed) == 1)
        // another key must not pass
        let other = try Hash58.fireWireID(fromHex: "000A2700212B8868")
        #expect(!(try Hash58.verify(database: signed, fireWireID: other).matches))
    }

    @Test("dates pass through the Mac epoch without loss")
    func datesSurvive() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        guard case .tracks(var tracks) = library.sections[0].content else { return }
        let added = MacTime.date(from: 3_861_691_370)
        tracks[0].dateAdded = added
        tracks[0].lastPlayed = MacTime.date(from: 3_812_625_239)
        library.sections[0].content = .tracks(tracks)

        let track = try #require(try ITunesDBParser.parse(ITunesDBWriter.serialize(library)).tracks.first)
        #expect(track.dateAdded == added)
        #expect(MacTime.value(from: track.lastPlayed) == 3_812_625_239)
    }
}

@Suite("field editing")
struct EditingTests {

    @Test("a new text record has a layout matching the database")
    func buildsTextMhod() {
        let mhod = Mhod.text(type: .sortArtist, value: "Weeknd")
        #expect(mhod.rawHeader.count == 24)
        #expect(Array(mhod.rawHeader.prefix(4)) == Array("mhod".utf8))
        #expect(mhod.text == "Weeknd")
        // 24 of header + 16 of prefix + 12 bytes of text
        #expect(mhod.byteCount == 52)
        // header bytes 0x10-0x17 are zeros across the database
        #expect(Array(mhod.rawHeader[16..<24]) == [UInt8](repeating: 0, count: 8))
        // UTF-16 encoding at payload+8
        #expect(Array(mhod.rawBody[8..<12]) == [1, 0, 0, 0])
    }

    @Test("an added field can be read after writing")
    func addedFieldRoundTrips() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        library = library.mappingTracks { $0.setting(.sortArtist, to: "Carson, Ken") }

        let reparsed = try ITunesDBParser.parse(ITunesDBWriter.serialize(library))
        let track = try #require(reparsed.tracks.first)
        #expect(track.sortArtist == "Carson, Ken")
        #expect(track.mhods.count == 6)          // there were five, one was added
        #expect(track.title == "Another Track")  // the rest untouched
        #expect(track.sortAlbum == "Great Chaos")
    }

    @Test("replacing an existing field does not change the record order")
    func replacementKeepsOrder() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        let before = try #require(library.tracks.first).mhods.map(\.type.rawValue)
        library = library.mappingTracks { $0.setting(.sortAlbum, to: "Something Else") }

        let track = try #require(try ITunesDBParser.parse(ITunesDBWriter.serialize(library)).tracks.first)
        #expect(track.mhods.map(\.type.rawValue) == before)
        #expect(track.sortAlbum == "Something Else")
    }

    @Test("a removed field disappears from the record")
    func removalWorks() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        library = library.mappingTracks { $0.setting(.sortAlbum, to: nil) }

        let track = try #require(try ITunesDBParser.parse(ITunesDBWriter.serialize(library)).tracks.first)
        #expect(track.sortAlbum == nil)
        #expect(track.mhods.count == 4)
        #expect(track.album == "A Great Chaos")
    }

    @Test("non-ASCII text survives writing and reading")
    func unicodeSurvives() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.oneTrackDatabase())
        let value = "Beyoncé — São Paulo · Ærøskøbing 🎧"
        library = library.mappingTracks { $0.setting(.title, to: value) }

        let track = try #require(try ITunesDBParser.parse(ITunesDBWriter.serialize(library)).tracks.first)
        #expect(track.title == value)
    }

    @Test("the repair aligns the outlying track with the majority")
    func repairAlignsOutlier() throws {
        var library = try ITunesDBParser.parse(DatabaseBuilder.threeTrackAlbum())
        #expect(library.albumsSplitOnDevice().count == 1)

        let changes = SortFieldRepair.plan(for: library)
        #expect(changes.count == 1)
        #expect(changes[0].from == "The Weeknd")
        #expect(changes[0].to == "Weeknd")

        library = SortFieldRepair.apply(changes, to: library)
        #expect(library.albumsSplitOnDevice().isEmpty)
        #expect(SortFieldRepair.plan(for: library).isEmpty)

        // the repair must not touch anything but the sort field
        let titles = library.tracks.map { $0.title ?? "" }.sorted()
        #expect(titles == ["First", "Third", "Second"].sorted())
    }
}

@Suite("duplication through the artist")
struct ArtistMismatchTests {

    private func library(albumArtist: String, artist: String) throws -> ITLibrary {
        let base = try ITunesDBParser.parse(DatabaseBuilder.threeTrackAlbum())
        return base.mappingTracks {
            $0.setting(.albumArtist, to: albumArtist).setting(.artist, to: artist)
        }
    }

    @Test("different names are reported")
    func differentNamesFlagged() throws {
        let flagged = try library(albumArtist: "Abel Tesfaye", artist: "The Weeknd")
            .albumsDuplicatedByArtistMismatch()
        #expect(flagged.count == 1)
        #expect(flagged.first?.albumArtist == "Abel Tesfaye")
        #expect(flagged.first?.trackCount == 3)
    }

    @Test("matching names are not reported")
    func matchingNamesIgnored() throws {
        #expect(try library(albumArtist: "The Weeknd", artist: "The Weeknd")
            .albumsDuplicatedByArtistMismatch().isEmpty)
    }

    @Test("a featured artist is not a mismatch")
    func featuringIsNotMismatch() throws {
        // ASTROWORLD has featured artists in the artist field and shows up once.
        #expect(try library(albumArtist: "Travis Scott", artist: "Travis Scott Feat. Drake")
            .albumsDuplicatedByArtistMismatch().isEmpty)
    }

    @Test("an empty album artist is not a mismatch")
    func emptyAlbumArtistIgnored() throws {
        let base = try ITunesDBParser.parse(DatabaseBuilder.threeTrackAlbum())
        let cleared = base.mappingTracks { $0.setting(.albumArtist, to: nil) }
        #expect(cleared.albumsDuplicatedByArtistMismatch().isEmpty)
    }

    @Test("case and diacritics do not create a mismatch")
    func foldingIgnored() throws {
        #expect(try library(albumArtist: "beyonce", artist: "Beyoncé")
            .albumsDuplicatedByArtistMismatch().isEmpty)
    }
}

/// Sections of a type we do not know. On the nano 2G Finder writes a type 9 section
/// with a 32-character identifier instead of a list - the parser failed on it, so
/// Clickwill did not open a database written by Finder.
@Suite("sections of an unknown type")
struct OpaqueSectionTests {

    /// A database with an appended type 9 section in the layout Finder uses.
    static func databaseWithType9() -> (data: Data, payload: [UInt8]) {
        var bytes = [UInt8](DatabaseBuilder.oneTrackDatabase())
        let payload = Array("0123456789abcdef0123456789abcdef".utf8)
        let headerLength = 96
        var section = [UInt8](repeating: 0, count: headerLength)
        section.replaceSubrange(0..<4, with: Array("mhsd".utf8))
        func put(_ value: UInt32, at offset: Int, in buffer: inout [UInt8]) {
            for i in 0..<4 { buffer[offset + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
        }
        put(UInt32(headerLength), at: 4, in: &section)
        put(UInt32(headerLength + payload.count), at: 8, in: &section)
        put(9, at: 0x0C, in: &section)
        bytes += section + payload
        let sections = UInt32(bytes[0x14]) | UInt32(bytes[0x15]) << 8
        put(UInt32(bytes.count), at: 8, in: &bytes)
        put(sections + 1, at: 0x14, in: &bytes)
        return (Data(bytes), payload)
    }

    @Test("a type 9 section reads as opaque and goes back byte for byte")
    func roundTrip() throws {
        let (data, payload) = Self.databaseWithType9()
        let library = try ITunesDBParser.parse(data)
        let extra = try #require(library.sections.last)
        #expect(extra.type == 9)
        guard case .opaque(let bytes) = extra.content else {
            Issue.record("a type 9 section should be opaque"); return
        }
        #expect(bytes == payload)
        #expect(library.tracks.count == 1, "the known sections read as before")
        #expect(ITunesDBWriter.serialize(library) == data)
    }

    @Test("editing tracks does not touch sections of an unknown type")
    func survivesEdits() throws {
        let (data, payload) = Self.databaseWithType9()
        let library = try ITunesDBParser.parse(data)
        let emptied = try library.removingTracks(uniqueIDs: Set(library.tracks.map(\.uniqueID)))
        let reparsed = try ITunesDBParser.parse(ITunesDBWriter.serialize(emptied))
        guard case .opaque(let bytes) = try #require(reparsed.sections.last).content else {
            Issue.record("the section disappeared after editing"); return
        }
        #expect(bytes == payload)
        #expect(reparsed.tracks.isEmpty)
    }
}
