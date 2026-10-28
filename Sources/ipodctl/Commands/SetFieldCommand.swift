import Foundation
import ITDBKit

/// `set-field --album A --field F --value V [--apply]` - setting a text
/// field for all tracks of an album; an empty value clears the field.
enum SetFieldCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        guard let album = call.value(for: "--album") else { throw CommandError("give --album") }
        guard let fieldName = call.value(for: "--field") else { throw CommandError("give --field") }
        let names: [String: MhodType] = [
            "albumartist": .albumArtist, "artist": .artist, "album": .album,
            "sortartist": .sortArtist, "sortalbum": .sortAlbum,
            "sortalbumartist": .sortAlbumArtist, "genre": .genre, "composer": .composer,
            "title": .title,
        ]
        guard let field = names[fieldName.lowercased()] else {
            throw CommandError("unknown field '\(fieldName)'. Available: \(names.keys.sorted().joined(separator: ", "))")
        }
        let raw = call.value(for: "--value")
        guard raw != nil else { throw CommandError("give --value (an empty string clears the field)") }
        let newValue = raw!.isEmpty ? nil : raw

        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let affected = library.tracks.filter { $0.album == album }
        guard !affected.isEmpty else { throw CommandError("there is no album '\(album)'") }

        let currently = Set(affected.map { $0.fields[field] })
        report("Field change", [
            ("album", album),
            ("field", field.label),
            ("tracks", "\(affected.count)"),
            ("now", currently.map { $0.map { "'\($0)'" } ?? "(empty)" }.sorted().joined(separator: ", ")),
            ("after the change", newValue.map { "'\($0)'" } ?? "(empty)"),
        ])

        guard call.has("--apply") else {
            print("\n  That was a preview. To write: add --apply")
            return
        }

        let ids = Set(affected.map(\.uniqueID))
        let updated = library.mappingTracks { track in
            ids.contains(track.uniqueID) ? track.setting(field, to: newValue) : track
        }
        announce(try await onDevice.write(updated, note: "\(field.label) in album '\(album)' -> \(newValue ?? "(empty)")"))
    }
}
