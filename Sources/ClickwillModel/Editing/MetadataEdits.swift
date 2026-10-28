import Foundation
import ITDBKit

/// An album field editable in the inspector. The change goes to all tracks of the card.
public enum AlbumField: String, CaseIterable, Sendable {
    case title = "Album"
    case albumArtist = "Album artist"
    case genre = "Genre"
    case year = "Year"
}

public enum MetadataError: Error, CustomStringConvertible {
    case invalidYear(String)
    public var description: String {
        switch self {
        case .invalidYear(let text): "invalid year \"\(text)\""
        }
    }
}

/// Metadata: titles, numbers, album fields, the compilation flag, merging
/// a split album.
extension LibraryEditor {

    // MARK: - Track

    /// Changes a track's title. The title table (criterion 3) stays the same
    /// permutation - the iPod shows the track under its new name in the old place of the
    /// "Songs" list until Music re-sorts it. The `sortTitle` field, if
    /// present, is removed, so it does not remain from the previous name.
    mutating func renameTrack(_ row: TrackRow, in album: AlbumCard, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != row.title else { return }
        library = library.mappingTracks { track in
            guard track.uniqueID == row.id else { return track }
            return track.setting(.title, to: title).setting(.sortTitle, to: nil)
        }
        recordChange(.trackEdited(album: self.title(of: album), track: row.displayTitle, field: "title", from: row.title, to: title))
    }

    /// Sets the track number (0 = none). Numbers decide the order within
    /// an album only after Music regenerates the tables; on the iPod what counts is
    /// the table, which `moveTracks` already sets.
    mutating func setTrackNumber(_ row: TrackRow, in album: AlbumCard, to number: UInt32) {
        guard number != row.number else { return }
        library = library.mappingTracks { track in
            guard track.uniqueID == row.id else { return track }
            var copy = track
            copy.trackNumber = number
            return copy
        }
        recordChange(.trackEdited(album: title(of: album), track: row.displayTitle, field: "track number",
                                   from: row.number == 0 ? "" : "\(row.number)", to: number == 0 ? "" : "\(number)"))
    }

    /// Numbers the album's tracks 1…N in table order.
    mutating func renumberTracks(in album: AlbumCard) throws {
        guard let album = catalog.block(for: album) else { throw AlbumOrderError.albumNotFound(album.title) }
        try catalog.requireSingleBlock(album)
        library = try library.renumberingTracks(album: album.title)
        recordChange(.tracksRenumbered(album: album.title, tracks: album.trackIndices.count))
    }

    // MARK: - Album

    /// Changes a field on all tracks of the card.
    mutating func setAlbumField(_ album: AlbumCard, _ field: AlbumField, to value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let album = current(album) else { return }
        let ids = Set(records(of: album).map(\.uniqueID))
        let before = Self.currentValue(of: field, in: album)
        guard value != before else { return }
        if field == .title, value.isEmpty { return }
        let year: UInt32? = field == .year ? (value.isEmpty ? 0 : UInt32(value)) : nil
        if field == .year, year == nil { throw MetadataError.invalidYear(value) }

        library = library.mappingTracks { track in
            guard ids.contains(track.uniqueID) else { return track }
            switch field {
            case .title:
                // Without `sortAlbum`, because it would remain from the previous name.
                return track.setting(.album, to: value).setting(.sortAlbum, to: nil)
            case .albumArtist:
                return track.setting(.albumArtist, to: value.isEmpty ? nil : value).setting(.sortAlbumArtist, to: nil)
            case .genre:
                return track.setting(.genre, to: value.isEmpty ? nil : value)
            case .year:
                var copy = track
                copy.year = year ?? 0
                return copy
            }
        }
        recordChange(.albumEdited(album: album.title, field: field.rawValue.lowercased(), from: before, to: value, tracks: ids.count))
    }

    /// Sets or clears the compilation flag on all tracks of the album.
    mutating func setCompilation(_ album: AlbumCard, _ flag: Bool) {
        let ids = Set(records(of: album).map(\.uniqueID))
        library = library.mappingTracks { track in
            guard ids.contains(track.uniqueID) else { return track }
            var copy = track
            copy.isCompilation = flag
            return copy
        }
        recordChange(.compilationChanged(album: title(of: album), isCompilation: flag, tracks: ids.count))
    }

    /// Merges the tracks of the `stray` card into the album `target`: aligns the album,
    /// the album artist with its sort fields, the compilation flag and the
    /// `mhia` record pointer, after which the cards are rebuilt as one.
    mutating func mergeAlbum(_ stray: AlbumCard, into target: AlbumCard) {
        guard let stray = current(stray), let target = current(target) else { return }
        let strayIDs = Set(records(of: stray).map(\.uniqueID))
        guard let model = records(of: target).first else { return }
        library = library.mappingTracks { track in
            guard strayIDs.contains(track.uniqueID) else { return track }
            // Sort fields also from the target album - the artist key groups
            // by them; an empty `sortAlbumArtist` while the rest have one filled
            // would still split the album.
            var copy = track.setting(.album, to: model.album).setting(.albumArtist, to: model.albumArtist)
                .setting(.sortAlbumArtist, to: model.sortAlbumArtist).setting(.sortAlbum, to: model.sortAlbum)
            copy.isCompilation = model.isCompilation
            copy.albumRecordIndex = model.albumRecordIndex
            return copy
        }
        recordChange(.albumMerged(album: target.title, artist: target.displayArtist, tracks: strayIDs.count))
    }

    static func currentValue(of field: AlbumField, in album: AlbumCard) -> String {
        switch field {
        case .title: return album.title
        case .albumArtist: return album.artist
        case .genre: return album.genre ?? ""
        case .year: return album.year.map(String.init) ?? ""
        }
    }
}
