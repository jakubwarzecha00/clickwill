import Foundation
import ITDBKit

/// `paths` - whether the paths from the database and from ArtworkDB pass the path check
/// (ContainedPath) - a real iPod must not lose files or artwork
/// because of it. Read-only.
enum PathsCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let library = try device.readLibrary()
        let manager = FileManager.default
        var ok = 0, refused: [String] = [], missing = 0
        for track in library.tracks {
            guard let relative = track.relativePath else { continue }
            if let url = track.fileURL(on: device.paths) {
                ok += 1
                if !manager.fileExists(atPath: url.path) { missing += 1 }
            } else {
                refused.append(relative)
            }
        }
        print("tracks: \(ok) pass (of which \(missing) without a file on disk), \(refused.count) rejected")
        for path in refused.prefix(10) { print("   rejected: \(path)") }
        var names: [String: Bool] = [:]
        var variants = 0, refusedVariants = 0
        for image in try device.readArtwork()?.images ?? [] {
            for variant in image.variants {
                variants += 1
                let passes = (try? variant.url(in: device.paths)) != nil && variant.hasSaneBounds
                if !passes { refusedVariants += 1 }
                names[variant.plainFileName] = passes
            }
        }
        print("artwork: \(variants) slices, \(refusedVariants) rejected; files: \(names.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value ? "ok" : "REJECTED")" }.joined(separator: ", "))")
    }
}
