import Foundation

/// The same three albums as in the core fixture, only assembled here, because
/// the fixture is internal to the ITDBKit tests.
/// `titles` and `extensions` replace the title and file extension of chosen
/// tracks (by `uniqueID`).
enum SyntheticLibrary {
  static func database(titles: [UInt32: String] = [:], extensions: [UInt32: String] = [:]) -> Data {
    let u32: (UInt32) -> [UInt8] = { v in [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
    let u64: (UInt64) -> [UInt8] = { v in (0..<8).map { UInt8((v >> (8 * $0)) & 0xFF) } }
    func header(_ sig: String, _ length: Int, _ total: Int, _ fields: [Int: [UInt8]]) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: length)
        for (i, c) in Array(sig.utf8).enumerated() { b[i] = c }
        b.replaceSubrange(4..<8, with: u32(UInt32(length))); b.replaceSubrange(8..<12, with: u32(UInt32(total)))
        for (o, v) in fields { b.replaceSubrange(o..<(o + v.count), with: v) }
        return b
    }
    func text(_ type: UInt32, _ s: String) -> [UInt8] {
        var body = u32(1) + u32(UInt32(s.utf16.count * 2)) + u32(1) + u32(0)
        for unit in s.utf16 { body += [UInt8(unit & 0xFF), UInt8(unit >> 8)] }
        return header("mhod", 24, 24 + body.count, [0x0C: u32(type)]) + body
    }
    struct T { let id: UInt32; let title, album, artist: String; let no: UInt32 }
    let tracks = [
        T(id: 10, title: "Bones", album: "The Bends", artist: "Radiohead", no: 2),
        T(id: 11, title: "Let Me Down", album: "Aftermath", artist: "Rolling Stones", no: 2),
        T(id: 12, title: "Planet Telex", album: "The Bends", artist: "Radiohead", no: 1),
        T(id: 13, title: "Paint It Black", album: "Aftermath", artist: "Rolling Stones", no: 1),
        T(id: 14, title: "Just", album: "The Bends", artist: "Radiohead", no: 3),
        T(id: 15, title: "Let It Happen", album: "Currents", artist: "Tame Impala", no: 1),
        T(id: 16, title: "Eventually", album: "Currents", artist: "Tame Impala", no: 2),
    ]
    let mhits: [UInt8] = tracks.flatMap { t -> [UInt8] in
        let mhods = text(1, titles[t.id] ?? t.title) + text(3, t.album) + text(4, t.artist)
            + text(2, ":iPod_Control:Music:F00:\(t.id).\(extensions[t.id] ?? "mp3")")
        return header("mhit", 624, 624 + mhods.count, [0x0C: u32(4), 0x10: u32(t.id), 0x28: u32(180_000), 0x2C: u32(t.no), 0x3C: u32(44_100 << 16), 0x70: u64(0x1000 + UInt64(t.id))]) + mhods
    }
    let order: [UInt32] = [3, 1, 2, 0, 4, 5, 6]
    var idx = u32(4) + u32(7); idx += [UInt8](repeating: 0, count: 48 - idx.count); for e in order { idx += u32(e) }
    let index = header("mhod", 24, 24 + idx.count, [0x0C: u32(52)]) + idx
    var jb = u32(4) + u32(3) + u32(0) + u32(0)
    for e in [(65, 0, 2), (66, 2, 3), (67, 5, 2)] as [(UInt32, UInt32, UInt32)] { jb += u32(e.0) + u32(e.1) + u32(e.2) }
    let jump = header("mhod", 24, 24 + jb.count, [0x0C: u32(53)]) + jb
    let mhips: [UInt8] = tracks.enumerated().flatMap { i, t -> [UInt8] in
        let m = header("mhod", 24, 32, [0x0C: u32(100)]) + u32(0) + u32(0)
        return header("mhip", 76, 76 + m.count, [0x0C: u32(1), 0x14: u32(UInt32(100 + i)), 0x18: u32(t.id)]) + m
    }
    let mhods = text(1, "iPod") + index + jump
    let playlist = header("mhyp", 184, 184 + mhods.count + mhips.count, [0x0C: u32(3), 0x10: u32(7), 0x14: [1], 0x18: u64(0xABCD)]) + mhods + mhips
    let trackSection = header("mhsd", 96, 96 + 92 + mhits.count, [0x0C: u32(1)]) + header("mhlt", 92, 7, [:]) + mhits
    let s3 = header("mhsd", 96, 96 + 92 + playlist.count, [0x0C: u32(3)]) + header("mhlp", 92, 1, [:]) + playlist
    let s2 = header("mhsd", 96, 96 + 92 + playlist.count, [0x0C: u32(2)]) + header("mhlp", 92, 1, [:]) + playlist
    let sections = trackSection + s3 + s2
    var head = [UInt8](repeating: 0, count: 244)
    for (i, c) in Array("mhbd".utf8).enumerated() { head[i] = c }
    head.replaceSubrange(4..<8, with: u32(244)); head.replaceSubrange(8..<12, with: u32(UInt32(244 + sections.count)))
    head.replaceSubrange(0x10..<0x14, with: u32(117)); head.replaceSubrange(0x14..<0x18, with: u32(3))
    head.replaceSubrange(0x18..<0x20, with: u64(0x1122_3344)); head.replaceSubrange(0x30..<0x32, with: [1, 0])
    return Data(head + sections)
}
}
