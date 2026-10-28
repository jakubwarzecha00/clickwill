import Foundation

/// Repair of sort fields that split an album into several covers.
///
/// The device groups covers by the pair of sort fields. It is enough for one track
/// of the album to have a different value, and the album appears twice in Cover Flow. The repair
/// brings all tracks of the album to the value the majority has.
///
/// The operation does not touch the order tables, so the track order stays unchanged.
public enum SortFieldRepair {

    public struct Change: Sendable {
        public let trackID: UInt32
        public let album: String
        public let title: String
        public let field: MhodType
        public let from: String?
        public let to: String?

        public var summary: String {
            let before = from.map { "'\($0)'" } ?? "(empty)"
            let after = to.map { "'\($0)'" } ?? "(empty)"
            return "\(field.label): \(before) -> \(after)"
        }
    }

    /// Works out what has to change. Writes nothing.
    public static func plan(for library: ITLibrary) -> [Change] {
        var changes: [Change] = []

        for (album, tracks) in Dictionary(grouping: library.tracks.filter({ !($0.album ?? "").isEmpty }),
                                          by: { $0.album ?? "" }) {
            let groups = Dictionary(grouping: tracks) { $0.deviceGroupingKey }
            guard groups.count > 1 else { continue }

            // The template is the key of the largest group. On a tie the
            // alphabetical order decides, so the result is repeatable.
            guard let target = groups
                .max(by: { ($0.value.count, $1.key.sortDescription) < ($1.value.count, $0.key.sortDescription) })?
                .key
            else { continue }

            for (key, outliers) in groups where key != target {
                for track in outliers {
                    if track.sortArtist != target.sortArtist {
                        changes.append(
                            Change(trackID: track.uniqueID, album: album, title: track.title ?? "",
                                   field: .sortArtist, from: track.sortArtist, to: target.sortArtist)
                        )
                    }
                    if track.sortAlbumArtist != target.sortAlbumArtist {
                        changes.append(
                            Change(trackID: track.uniqueID, album: album, title: track.title ?? "",
                                   field: .sortAlbumArtist, from: track.sortAlbumArtist, to: target.sortAlbumArtist)
                        )
                    }
                }
            }
        }
        return changes.sorted { ($0.album, $0.title, $0.field.rawValue) < ($1.album, $1.title, $1.field.rawValue) }
    }

    /// Applies the computed changes to a copy of the library.
    public static func apply(_ changes: [Change], to library: ITLibrary) -> ITLibrary {
        var byTrack: [UInt32: [Change]] = [:]
        for change in changes { byTrack[change.trackID, default: []].append(change) }

        return library.mappingTracks { track in
            guard let pending = byTrack[track.uniqueID] else { return track }
            return pending.reduce(track) { $0.setting($1.field, to: $1.to) }
        }
    }
}

extension DeviceGroupingKey {
    /// A stable order for breaking ties.
    var sortDescription: String { "\(sortAlbumArtist ?? "")\u{0}\(sortArtist ?? "")" }
}
