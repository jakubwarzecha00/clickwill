import Foundation
import ClickwillModel

/// A sentence about a change in the change list. The model keeps the change itself (`PendingChange.Kind`);
/// the app decides how to describe it.
extension PendingChange {
    var summary: String {
        switch kind {
        case .albumMoved(let album, let from, let to):
            return "Move “\(album)” from position \(from + 1) to \(to + 1)"
        case .trackMoved(let album, let track, let from, let to):
            return "In “\(album)”: move “\(track)” from \(from + 1) to \(to + 1)"
        case .trackDeleted(let album, let track, let fileOnDisk):
            return "Delete “\(track)” from “\(album)”" + (fileOnDisk ? "" : " (entry without a file)")
        case .compilationChanged(let album, let flag, let tracks):
            return (flag ? "Mark “\(album)” as a compilation" : "Take “\(album)” out of Compilations") + " (\(songs(tracks)))"
        case .trackEdited(let album, let track, let field, let from, let to):
            // For a title, the old title is the same name as the track - without this
            // it came out as "title of “Crazy Train” “Crazy Train” → …".
            if field == "title" { return "In “\(album)”: rename “\(from)” to “\(to)”" }
            // An empty value is a field without a value - without this it came out as ", – → 3".
            if from.isEmpty { return "In “\(album)”: set the \(field) of “\(track)” to \(to)" }
            if to.isEmpty { return "In “\(album)”: clear the \(field) of “\(track)” (was \(from))" }
            return "In “\(album)”: \(field) of “\(track)”, \(from) → \(to)"
        case .albumEdited(let album, let field, let from, let to, let tracks):
            // Without this an empty genre came out as "genre “” → “Ambient”".
            if from.isEmpty { return "“\(album)”: set \(field) to “\(to)” (\(songs(tracks)))" }
            if to.isEmpty { return "“\(album)”: clear \(field) “\(from)” (\(songs(tracks)))" }
            return "“\(album)”: \(field) “\(from)” → “\(to)” (\(songs(tracks)))"
        case .tracksRenumbered(let album, let tracks):
            return "Renumber “\(album)” 1…\(tracks)"
        case .artworkReplaced(let album, let slots, let tracks):
            return "Replace the cover of “\(album)” (\(slots) image sizes, \(songs(tracks)))"
        case .artworkAdded(let album, let tracks):
            return "Add a cover to “\(album)” (\(songs(tracks)); new artwork record on the iPod)"
        case .artworkShared(let album, let tracks):
            return "Show the cover of “\(album)” on \(tracks == 1 ? "1 more song" : "\(tracks) more songs")"
        case .albumMerged(let album, let artist, let tracks):
            return "Merge \(tracks) stray \(tracks == 1 ? "song" : "songs") into “\(album)” by \(artist)"
        case .trackConverted(let album, let track, let from, let to, let original):
            let saved = original.map { ", original kept in \($0)" } ?? ", no copy of the original"
            return "Convert “\(track)” in “\(album)” from \(from.isEmpty ? "its current format" : from) to \(to)\(saved)"
        case .albumDeleted(let album, let artist, let tracks, let files, let copies):
            let saved = copies.map { ", copies kept in \($0)" } ?? (files > 0 ? ", \(files) files erased from the iPod" : "")
            return "Delete the album “\(album)” by \(artist) (\(songs(tracks))\(saved))"
        case .duplicatesMerged(let songs, let files, let copies):
            let copiesText = songs == 1 ? "1 extra copy" : "\(songs) extra copies"
            let saved = copies.map { ", the files saved in \($0)" } ?? (files > 0 ? ", \(files) files erased from the iPod" : "")
            return "Merge duplicate songs: remove \(copiesText), keeping plays, ratings and playlists on the copy that stays\(saved)"
        case .filesLeftToDelete(let files):
            return "Erase \(files == 1 ? "1 file" : "\(files) files") the last write couldn't delete from the iPod"
        case .filesRestored(let tracks, let albums, let converting):
            let songs = tracks == 1 ? "1 entry" : "\(tracks) entries"
            let where_ = albums == 1 ? "1 album" : "\(albums) albums"
            let converted = converting > 0 ? ", \(converting) to be converted first" : ""
            return "Give \(songs) back a file (\(where_)\(converted))"
        case .filesReplaced(let tracks, let albums, let converting):
            let songs = tracks == 1 ? "1 song" : "\(tracks) songs"
            let where_ = albums == 1 ? "1 album" : "\(albums) albums"
            let converted = converting > 0 ? ", \(converting) to be converted first" : ""
            return "Replace the audio file of \(songs) (\(where_)\(converted)). The old files are erased after the write"
        case .tracksAdded(let tracks, let albums, let bytes, let converting):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let where_ = albums == 1 ? "1 album" : "\(albums) albums"
            let converted = converting > 0 ? ", \(converting) to be converted first" : ""
            return "Add \(songs(tracks)) (\(where_), \(size)\(converted))"
        }
    }

    private func songs(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }
}
