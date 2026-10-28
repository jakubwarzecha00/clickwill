import Foundation
@testable import ITDBKit

/// A synthetic database with a few tracks, the master playlist, an album browse table
/// and a jump bar - in two sections, as in a real file.
/// The header layout matches what the parser reads from an iPod Classic.
enum LibraryFixture {

    struct Track {
        let id: UInt32
        let title: String
        let album: String
        let artist: String
        let number: UInt32
        var sortAlbum: String? = nil
        var kind: TrackFileKind = .mp3
    }

    static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
    static func u64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8((value >> (8 * $0)) & 0xFF) } }

    static func textMhod(type: UInt32, _ text: String) -> [UInt8] {
        var body = u32(1) + u32(UInt32(text.utf16.count * 2)) + u32(1) + u32(0)
        for unit in text.utf16 { body += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        return header("mhod", length: 24, total: 24 + body.count, fields: [0x0C: u32(type)]) + body
    }

    static func header(_ signature: String, length: Int, total: Int, fields: [Int: [UInt8]]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        for (index, byte) in Array(signature.utf8).enumerated() { bytes[index] = byte }
        bytes.replaceSubrange(4..<8, with: u32(UInt32(length)))
        bytes.replaceSubrange(8..<12, with: u32(UInt32(total)))
        for (offset, value) in fields { bytes.replaceSubrange(offset..<(offset + value.count), with: value) }
        return bytes
    }

    static func container(_ signature: String, length: Int, fields: [Int: [UInt8]], children: [UInt8]) -> [UInt8] {
        header(signature, length: length, total: length + children.count, fields: fields) + children
    }

    /// A list: at offset 8 the number of children, not a length.
    static func list(_ signature: String, length: Int, count: Int) -> [UInt8] {
        header(signature, length: length, total: count, fields: [:])
    }

    /// The album record number the track points to (0x120) - computed the same way
    /// as in `albumSection`: the order of the album's first appearance.
    static func albumIndex(of track: Track, in tracks: [Track]) -> UInt32 {
        var seen: [String] = []
        for candidate in tracks where !seen.contains(candidate.album) { seen.append(candidate.album) }
        return UInt32((seen.firstIndex(of: track.album) ?? 0) + 1)
    }

    static func mhit(_ track: Track, albumIndex: UInt32 = 0) -> [UInt8] {
        var mhods = textMhod(type: 1, track.title)
            + textMhod(type: 3, track.album)
            + textMhod(type: 4, track.artist)
            + textMhod(type: 6, track.kind.fileTypeDescription)
            + textMhod(type: 2, ":iPod_Control:Music:F00:\(track.id).\(track.kind.fileExtension)")
        var count: UInt32 = 5
        if let sort = track.sortAlbum { mhods += textMhod(type: 28, sort); count += 1 }
        let code = Array(track.kind.fourCharacterCode.utf8).reversed().map { $0 }
        return container("mhit", length: 624, fields: [
            0x0C: u32(count), 0x10: u32(track.id), 0x18: code,
            0x1D: [track.kind == .mp3 ? 1 : 0], 0x2C: u32(track.number),
            0x3C: u32(44_100 << 16), 0x70: u64(0x1000 + UInt64(track.id)),
            0x120: u32(albumIndex),
        ], children: mhods)
    }

    static func browseIndex(criterion: UInt32, _ entries: [UInt32]) -> [UInt8] {
        var body = u32(criterion) + u32(UInt32(entries.count))
        body += [UInt8](repeating: 0, count: 48 - body.count)
        for entry in entries { body += u32(entry) }
        return header("mhod", length: 24, total: 24 + body.count, fields: [0x0C: u32(52)]) + body
    }

    static func jumpTable(criterion: UInt32, _ entries: [(UInt32, UInt32, UInt32)]) -> [UInt8] {
        var body = u32(criterion) + u32(UInt32(entries.count)) + u32(0) + u32(0)
        for entry in entries { body += u32(entry.0) + u32(entry.1) + u32(entry.2) }
        return header("mhod", length: 24, total: 24 + body.count, fields: [0x0C: u32(53)]) + body
    }

    static func mhip(order: UInt32, trackID: UInt32) -> [UInt8] {
        let mhod = header("mhod", length: 24, total: 24 + 4 + 4, fields: [0x0C: u32(100)]) + u32(0) + u32(0)
        return container("mhip", length: 76, fields: [
            0x0C: u32(1), 0x14: u32(order), 0x18: u32(trackID),
        ], children: mhod)
    }

    static func masterPlaylist(tracks: [Track], albumOrder: [UInt32], jump: [(UInt32, UInt32, UInt32)]) -> [UInt8] {
        let mhods = textMhod(type: 1, "iPod")
            + browseIndex(criterion: 4, albumOrder)
            + jumpTable(criterion: 4, jump)
        let entries = tracks.enumerated().flatMap { mhip(order: UInt32(100 + $0.offset), trackID: $0.element.id) }
        return container("mhyp", length: 184, fields: [
            0x0C: u32(3), 0x10: u32(UInt32(tracks.count)), 0x14: [1], 0x18: u64(0xABCD),
        ], children: mhods + entries)
    }

    /// Assembles the database. `albumOrder` is the track positions (indices into `tracks`) in display
    /// order; `jump` is the jump bar for that order.
    static func mhia(index: UInt16, title: String, artist: String) -> [UInt8] {
        let mhods = textMhod(type: 200, title) + textMhod(type: 201, artist)
        return container("mhia", length: 88, fields: [
            0x0C: u32(2), 0x10: [UInt8(index & 0xFF), UInt8(index >> 8)],
            0x18: u64(0x2000 + UInt64(index)),
        ], children: mhods)
    }

    /// Albums in the order in which the device keeps them - the record number
    /// matches the track's field 0x120.
    static func albumSection(_ albums: [(String, String)]) -> [UInt8] {
        let records = albums.enumerated().flatMap { mhia(index: UInt16($0.offset + 1), title: $0.element.0, artist: $0.element.1) }
        return container("mhsd", length: 96, fields: [0x0C: u32(4)],
            children: list("mhla", length: 92, count: albums.count) + records)
    }

    static func database(tracks: [Track], albumOrder: [UInt32], jump: [(UInt32, UInt32, UInt32)]) -> Data {
        let trackSection = container("mhsd", length: 96, fields: [0x0C: u32(1)],
            children: list("mhlt", length: 92, count: tracks.count)
                + tracks.flatMap { mhit($0, albumIndex: albumIndex(of: $0, in: tracks)) })
        let playlist = masterPlaylist(tracks: tracks, albumOrder: albumOrder, jump: jump)
        let playlistSection3 = container("mhsd", length: 96, fields: [0x0C: u32(3)],
            children: list("mhlp", length: 92, count: 1) + playlist)
        let playlistSection2 = container("mhsd", length: 96, fields: [0x0C: u32(2)],
            children: list("mhlp", length: 92, count: 1) + playlist)

        var albums: [(String, String)] = []
        for track in tracks where !albums.contains(where: { $0.0 == track.album }) {
            albums.append((track.album, track.artist))
        }
        let sections = trackSection + playlistSection3 + playlistSection2 + albumSection(albums)
        var head = [UInt8](repeating: 0, count: 244)
        for (index, byte) in Array("mhbd".utf8).enumerated() { head[index] = byte }
        head.replaceSubrange(4..<8, with: u32(244))
        head.replaceSubrange(8..<12, with: u32(UInt32(244 + sections.count)))
        head.replaceSubrange(0x10..<0x14, with: u32(117))
        head.replaceSubrange(0x14..<0x18, with: u32(4))
        head.replaceSubrange(0x18..<0x20, with: u64(0x1122_3344))
        head.replaceSubrange(0x30..<0x32, with: [1, 0])
        return Data(head + sections)
    }

    /// Three albums: Aftermath (2 tracks), Bends (3, sortAlbum without "The"), Currents (2).
    /// The table laid out alphabetically, with tracks by number.
    static let tracks: [Track] = [
        Track(id: 10, title: "Bones", album: "The Bends", artist: "Radiohead", number: 2, sortAlbum: "Bends"),
        Track(id: 11, title: "Let Me Down", album: "Aftermath", artist: "Rolling Stones", number: 2),
        Track(id: 12, title: "Planet Telex", album: "The Bends", artist: "Radiohead", number: 1, sortAlbum: "Bends"),
        Track(id: 13, title: "Paint It Black", album: "Aftermath", artist: "Rolling Stones", number: 1),
        Track(id: 14, title: "Just", album: "The Bends", artist: "Radiohead", number: 3, sortAlbum: "Bends"),
        Track(id: 15, title: "Let It Happen", album: "Currents", artist: "Tame Impala", number: 1),
        Track(id: 16, title: "Eventually", album: "Currents", artist: "Tame Impala", number: 2),
    ]
    static let alphabeticalOrder: [UInt32] = [3, 1, 2, 0, 4, 5, 6]
    static let alphabeticalJump: [(UInt32, UInt32, UInt32)] = [(65, 0, 2), (66, 2, 3), (67, 5, 2)]

    static func standard() throws -> ITLibrary {
        try ITunesDBParser.parse(database(tracks: tracks, albumOrder: alphabeticalOrder, jump: alphabeticalJump))
    }
}
