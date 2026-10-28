import Foundation
import ITDBKit

/// `dump [--out FILE]` - the whole library as JSON.
enum DumpCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let export = LibraryExport.make(from: try device.readLibrary())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        if let path = call.value(for: "--out") {
            try data.write(to: URL(fileURLWithPath: path))
            print("Wrote \(data.count) B to \(path)")
        } else {
            FileHandle.standardOutput.write(data)
        }
    }
}
