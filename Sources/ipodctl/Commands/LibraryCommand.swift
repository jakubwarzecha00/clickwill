import Foundation
import ITDBKit

/// `library` - a library summary.
enum LibraryCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let library = try device.readLibrary()
        let groups = library.albumGroups()
        let inconsistent = groups.filter { Set($0.value.map { $0.sortAlbum ?? "" }).count > 1 }
        let withSortKey = groups.filter { $0.value.contains { $0.sortAlbum != nil } }
        let seconds = library.tracks.reduce(0.0) { $0 + $1.duration }

        report("Library", [
            ("device", library.deviceName ?? "(no name)"),
            ("database version", "\(library.version)"),
            ("tracks", "\(library.tracks.count)"),
            ("total time", String(format: "%.1f h", seconds / 3600)),
            ("albums (from track fields)", "\(groups.count)"),
            ("albums (mhla index)", "\(library.albums.count)"),
            ("with a sort key", "\(withSortKey.count)"),
            ("with an inconsistent key", "\(inconsistent.count)"),
            ("playlists", "\(library.playlists.count)"),
        ])

        print("\nLargest albums")
        for (key, tracks) in groups.sorted(by: { $0.value.count > $1.value.count }).prefix(5) {
            print("  \(tracks.count) tracks  \(key.album) / \(key.albumArtist)")
        }
        print("\nPlaylists")
        for playlist in library.playlists {
            print("  \(playlist.name ?? "(untitled)")  \(playlist.trackCount) items\(playlist.isMaster ? "  [master]" : "")")
        }
        if !inconsistent.isEmpty {
            print("\nAlbums with an inconsistent sort key")
            for (key, tracks) in inconsistent.prefix(5) {
                print("  \(key.album) / \(key.albumArtist)  (\(tracks.count) tracks)")
            }
        }

        let split = library.albumsSplitOnDevice()
        if split.isEmpty {
            print("\nNo album splits into separate covers.")
        } else {
            print("\nAlbums split into separate covers (inconsistent sort fields)")
            for album in split {
                print("  \(album.album) - \(album.groups.count) covers")
                for group in album.groups {
                    let numbers = group.tracks.map(\.trackNumber).sorted()
                    print("      \(group.tracks.count) tracks, \(group.key.description)")
                    print("          track numbers \(numbers.prefix(10).map(String.init).joined(separator: ", "))")
                }
            }
        }

        let duplicated = library.albumsDuplicatedByArtistMismatch()
        if duplicated.isEmpty {
            print("\nNo album appears twice because of an artist mismatch.")
        } else {
            print("\nAlbums appearing twice in Cover Flow (the album artist is a different name than the track artist)")
            for album in duplicated {
                print("  \(album.album) - \(album.trackCount) tracks")
                print("      album artist: '\(album.albumArtist)'")
                print("      track artists: \(album.artists.map { "'\($0)'" }.joined(separator: ", "))")
            }
        }

        let mixed = library.albumsWithMixedOrder()
        if !mixed.isEmpty {
            print("\nAlbums with a mixed-up order (inconsistent album artist)")
            print("  \(mixed.count) albums - the iPod lays them out in blocks instead of by track number")
            for album in mixed.prefix(6) {
                let blocks = album.blocks.map { block in
                    "\(block.tracks.count)x \(block.artist.isEmpty ? "(empty)" : block.artist)"
                }
                print("  \(album.album): \(blocks.joined(separator: "  |  "))")
            }
        }
    }
}
