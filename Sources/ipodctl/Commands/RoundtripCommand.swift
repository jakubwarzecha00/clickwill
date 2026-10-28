import Foundation
import ITDBKit

/// `roundtrip [--file DATABASE --guid HEX]` - GATE: whether the writer reproduces the database byte for byte.
enum RoundtripCommand {
    static func run(_ call: Invocation) async throws {
        // --file allows checking any database, including one from a backup.
        // The GUID is then given explicitly - it is the signing key of a specific iPod.
        let fireWireID: [UInt8]?
        let original: Data
        if let path = call.value(for: "--file") {
            original = try Data(contentsOf: URL(fileURLWithPath: path))
            fireWireID = try call.value(for: "--guid").map(Hash58.fireWireID(fromHex:))
        } else {
            let device = try openDevice(call)
            original = try device.readDatabase()
            fireWireID = device.fireWireID?.bytes
        }
        let library = try ITunesDBParser.parse(original)
        // The signature according to the format that lies in the file. A database we cannot
        // sign is compared without a signature - reading and assembling can be checked
        // on every generation before any of them gets a write module.
        let format = try DatabaseFormat.detect(header: original)
        let serialized = ITunesDBWriter.serialize(library)
        let rebuilt: Data
        if format.signing == .hash58 {
            guard fireWireID != nil else { throw CommandError("a hash58 database - give --guid <16 hex characters>") }
            rebuilt = try DatabaseSigner(format: format, fireWireID: fireWireID).sign(serialized)
        } else {
            print("  format \(format.name): comparison without a signature")
            rebuilt = serialized
        }

        report("Round-trip gate", [
            ("original", "\(original.count) B"),
            ("rebuilt", "\(rebuilt.count) B"),
            ("tracks", "\(library.tracks.count)"),
            ("playlists", "\(library.playlists.count)"),
            ("albums in the index", "\(library.albums.count)"),
        ])

        guard original.count == rebuilt.count else {
            let delta = rebuilt.count - original.count
            throw CommandError("the size differs by \(delta) B - the writer loses or adds data")
        }

        let a = [UInt8](original), b = [UInt8](rebuilt)
        var differences: [Int] = []
        for index in a.indices where a[index] != b[index] {
            differences.append(index)
            if differences.count > 4096 { break }
        }

        if differences.isEmpty {
            print("\n  IDENTICAL TO THE BYTE - the writer reproduces the database unchanged.")
            return
        }

        print("\n  DIFFERENCES: \(differences.count)\(differences.count > 4096 ? "+" : "") bytes")
        // We group them into continuous areas, so it is visible which fields drifted
        var runs: [(Int, Int)] = []
        for index in differences {
            if let last = runs.last, index == last.1 { runs[runs.count - 1].1 = index + 1 }
            else { runs.append((index, index + 1)) }
        }
        for (start, end) in runs.prefix(12) {
            let slice = { (data: [UInt8]) in
                data[start..<min(end, start + 16)].map { String(format: "%02x", $0) }.joined(separator: " ")
            }
            print("    @\(String(format: "%#08x", start)) (\(end - start) B)")
            print("        original: \(slice(a))")
            print("        rebuilt:  \(slice(b))")
        }
        if runs.count > 12 { print("    ... and \(runs.count - 12) more areas") }
        throw CommandError("the writer does not reproduce the database - nothing may be written")
    }
}
