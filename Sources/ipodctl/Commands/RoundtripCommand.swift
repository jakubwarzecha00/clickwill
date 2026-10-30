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
        if try DatabaseFormat.detect(header: original).signing == .hash58, fireWireID == nil {
            throw CommandError("a hash58 database - give --guid <16 hex characters>")
        }
        let trip = try RoundTrip.measure(original, fireWireID: fireWireID)
        if !trip.signed {
            print("  format \(try DatabaseFormat.detect(header: original).name): comparison without a signature")
        }
        let library = try ITunesDBParser.parse(original)

        report("Round-trip gate", [
            ("original", "\(trip.original.count) B"),
            ("rebuilt", "\(trip.rebuilt.count) B"),
            ("tracks", "\(library.tracks.count)"),
            ("playlists", "\(library.playlists.count)"),
            ("albums in the index", "\(library.albums.count)"),
        ])

        guard trip.original.count == trip.rebuilt.count else {
            let delta = trip.rebuilt.count - trip.original.count
            throw CommandError("the size differs by \(delta) B - the writer loses or adds data")
        }

        if trip.isIdentical {
            print("\n  IDENTICAL TO THE BYTE - the writer reproduces the database unchanged.")
            return
        }

        // Grouped into continuous areas, so it is visible which fields drifted.
        let runs = trip.differingRegions()
        let a = [UInt8](trip.original), b = [UInt8](trip.rebuilt)
        let count = runs.reduce(0) { $0 + $1.count }
        print("\n  DIFFERENCES: \(count)\(count >= 4096 ? "+" : "") bytes")
        for run in runs.prefix(12) {
            let slice = { (data: [UInt8]) in
                data[run.lowerBound..<min(run.upperBound, run.lowerBound + 16)].map { String(format: "%02x", $0) }.joined(separator: " ")
            }
            print("    @\(String(format: "%#08x", run.lowerBound)) (\(run.count) B)")
            print("        original: \(slice(a))")
            print("        rebuilt:  \(slice(b))")
        }
        if runs.count > 12 { print("    ... and \(runs.count - 12) more areas") }
        throw CommandError("the writer does not reproduce the database - nothing may be written")
    }
}
