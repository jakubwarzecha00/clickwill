import Foundation
import ITDBKit
import ClickwillModel

/// `duplicates [--snapshot FOLDER]` - the same duplicate groups the app
/// shows in "Review Duplicates". Read-only; `--snapshot` reads
/// files/iTunes/iTunesDB from a backup instead of from the iPod.
enum DuplicatesCommand {
    static func run(_ call: Invocation) async throws {
        let library: ITLibrary
        if let snapshot = call.value(for: "--snapshot") {
            let url = URL(fileURLWithPath: snapshot).appendingPathComponent("files/iTunes/iTunesDB")
            library = try ITunesDBParser.parse(Data(contentsOf: url))
        } else {
            library = try openDevice(call).readLibrary()
        }
        let clusters = LibraryModel.duplicateClusters(library.tracks, missing: [], unsupported: [])
        for cluster in clusters {
            let first = cluster[0]
            print("\(first.title ?? "?") | \(first.artist ?? first.albumArtist ?? "?") | \(first.album ?? "?")")
            for (index, track) in cluster.enumerated() {
                let seconds = Double(track.durationMilliseconds) / 1000
                print("   \(index == 0 ? "keep" : "remove") \(LibraryModel.formatGuess(track)), \(String(format: "%.1f", seconds)) s, \(track.playCount) plays, \(track.relativePath ?? "no file")")
            }
        }
        print("groups: \(clusters.count), copies to remove: \(clusters.reduce(0) { $0 + $1.count - 1 }), tracks: \(library.tracks.count)")
    }
}
