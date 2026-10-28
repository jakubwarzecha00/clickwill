import Foundation

/// A flat, serializable form of the library. The working model keeps the raw bytes
/// of every record, which make no sense to push into JSON - hence separate types.
public enum LibraryExport {

    public struct Track: Codable, Sendable {
        public let uniqueID: UInt32
        public let title: String?
        public let artist: String?
        public let albumArtist: String?
        public let album: String?
        public let genre: String?
        public let composer: String?
        public let sortTitle: String?
        public let sortAlbum: String?
        public let sortArtist: String?
        public let sortAlbumArtist: String?
        public let trackNumber: UInt32
        public let totalTracks: UInt32
        public let discNumber: UInt32
        public let totalDiscs: UInt32
        public let year: UInt32
        public let durationSeconds: Double
        public let sizeBytes: UInt32
        public let bitRate: UInt32
        public let sampleRate: UInt32
        public let playCount: UInt32
        public let rating: UInt8
        public let dateAdded: Date?
        public let lastPlayed: Date?
        public let path: String?
    }

    public struct PlaylistEntry: Codable, Sendable {
        public let trackID: UInt32
        public let order: UInt32
    }

    public struct Playlist: Codable, Sendable {
        public let name: String?
        public let isMaster: Bool
        public let persistentID: String
        public let entries: [PlaylistEntry]
    }

    public struct Album: Codable, Sendable {
        public let index: UInt16
        public let persistentID: String
        public let title: String?
        public let artist: String?
        public let sortArtist: String?
    }

    public struct AlbumGroup: Codable, Sendable {
        public let album: String
        public let albumArtist: String
        public let trackCount: Int
        public let sortAlbum: String?
        /// `true` if the tracks of this album have different sort keys -
        /// then the iPod splits it into several items in the menu.
        public let hasInconsistentSortKey: Bool
    }

    public struct Library: Codable, Sendable {
        public let version: UInt32
        public let databaseID: String
        public let hashingScheme: UInt16
        public let deviceName: String?
        public let sourceByteCount: Int
        public let tracks: [Track]
        public let playlists: [Playlist]
        public let albumIndex: [Album]
        public let albumGroups: [AlbumGroup]
    }

    public static func make(from library: ITLibrary) -> Library {
        let groups = library.albumGroups()
            .map { key, tracks -> AlbumGroup in
                let sortKeys = Set(tracks.map { $0.sortAlbum ?? "" })
                return AlbumGroup(
                    album: key.album,
                    albumArtist: key.albumArtist,
                    trackCount: tracks.count,
                    sortAlbum: sortKeys.count == 1 ? sortKeys.first.flatMap { $0.isEmpty ? nil : $0 } : nil,
                    hasInconsistentSortKey: sortKeys.count > 1
                )
            }
            .sorted { ($0.albumArtist, $0.album) < ($1.albumArtist, $1.album) }

        return Library(
            version: library.version,
            databaseID: String(format: "%016llx", library.databaseID),
            hashingScheme: library.hashingScheme,
            deviceName: library.deviceName,
            sourceByteCount: library.sourceByteCount,
            tracks: library.tracks.map { track in
                Track(
                    uniqueID: track.uniqueID,
                    title: track.title, artist: track.artist,
                    albumArtist: track.albumArtist, album: track.album,
                    genre: track.genre, composer: track.composer,
                    sortTitle: track.sortTitle, sortAlbum: track.sortAlbum,
                    sortArtist: track.sortArtist, sortAlbumArtist: track.sortAlbumArtist,
                    trackNumber: track.trackNumber, totalTracks: track.totalTracks,
                    discNumber: track.discNumber, totalDiscs: track.totalDiscs,
                    year: track.year, durationSeconds: track.duration,
                    sizeBytes: track.sizeBytes, bitRate: track.bitRate,
                    sampleRate: track.sampleRate, playCount: track.playCount,
                    rating: track.rating, dateAdded: track.dateAdded,
                    lastPlayed: track.lastPlayed, path: track.relativePath
                )
            },
            playlists: library.playlists.map { playlist in
                Playlist(
                    name: playlist.name,
                    isMaster: playlist.isMaster,
                    persistentID: String(format: "%016llx", playlist.persistentID),
                    entries: playlist.entries.map { PlaylistEntry(trackID: $0.trackID, order: $0.order) }
                )
            },
            albumIndex: library.albums.map {
                Album(
                    index: $0.index,
                    persistentID: String(format: "%016llx", $0.persistentID),
                    title: $0.title, artist: $0.artist, sortArtist: $0.sortArtist
                )
            },
            albumGroups: groups
        )
    }
}
