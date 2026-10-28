import Foundation
import ITDBKit
import ClickwillModel

/// `coverflow [--snapshot FOLDER] [--artist X]` - the Cover Flow strip as
/// Clickwill (and the iPod) will show it. Read-only; `--snapshot` reads a
/// backup instead of the connected iPod, `--artist` narrows the list.
enum CoverFlowCommand {
    static func run(_ call: Invocation) async throws {
        let source: LibrarySource
        if let snapshot = call.value(for: "--snapshot") { source = .snapshot(URL(fileURLWithPath: snapshot)) }
        else { source = .device(try openDevice(call)) }
        let model = await MainActor.run { LibraryModel() }
        await model.load(source)
        let artist = call.value(for: "--artist")?.lowercased()
        let albums = await MainActor.run { model.coverFlowAlbums }
        for (position, album) in albums.enumerated()
        where artist.map({ album.artist.lowercased().contains($0) }) ?? true {
            print(String(format: "%4d  ", position + 1) + "\(album.displayArtist) - \(album.displayTitle)" + (album.isCompilation ? "  [compilation]" : ""))
        }
    }
}
