import Foundation
import ITDBKit

/// Tracks that already exist - on the iPod or in the add queue - collected so that
/// an import can ask about each file before it reaches the device.
///
/// We compare metadata, not bytes: a file on the iPod is sometimes transcoded
/// (FLAC → ALAC), so the same song has a different checksum and a different
/// size there. The title, artist and album must match after simplification
/// (case, accents, spaces), and the length - within two seconds, because
/// an encoder can add or cut a few dozen milliseconds of silence. The album
/// is in the key on purpose: the same track on a compilation is a separate item.
public struct SongIndex: Sendable {
    public enum Place: Sendable, Equatable {
        case onIPod
        case queued
    }

    struct Key: Hashable, Sendable {
        let title: String
        let artist: String
        let album: String
    }

    /// The allowed length difference.
    static let durationTolerance: UInt32 = 2_000

    private var entries: [Key: [(duration: UInt32, place: Place)]] = [:]

    public init() {}

    public init(tracks: [ITTrack], queued: [TrackDraft] = []) {
        for track in tracks {
            insert(title: track.title, artist: track.artist ?? track.albumArtist, album: track.album,
                   duration: track.durationMilliseconds, place: .onIPod)
        }
        for draft in queued { insert(draft, place: .queued) }
    }

    mutating func insert(_ draft: TrackDraft, place: Place) {
        insert(title: draft.title, artist: draft.artist ?? draft.albumArtist, album: draft.album,
               duration: draft.durationMilliseconds, place: place)
    }

    private mutating func insert(title: String?, artist: String?, album: String?, duration: UInt32, place: Place) {
        guard let key = Self.key(title: title, artist: artist, album: album) else { return }
        entries[key, default: []].append((duration, place))
    }

    /// Where this song already is. `onIPod` wins over `queued` - it is the more important news.
    public func place(of draft: TrackDraft) -> Place? {
        guard let key = Self.key(title: draft.title, artist: draft.artist ?? draft.albumArtist, album: draft.album),
              let known = entries[key] else { return nil }
        let matching = known.filter { Self.sameLength($0.duration, draft.durationMilliseconds) }
        if matching.contains(where: { $0.place == .onIPod }) { return .onIPod }
        return matching.isEmpty ? nil : .queued
    }

    /// A missing length on either side does not decide - then the names are enough.
    static func sameLength(_ a: UInt32, _ b: UInt32) -> Bool {
        guard a > 0, b > 0 else { return true }
        return (a > b ? a - b : b - a) <= durationTolerance
    }

    /// Without a title there is nothing to compare - such a file is not marked.
    static func key(title: String?, artist: String?, album: String?) -> Key? {
        let title = normalized(title)
        guard !title.isEmpty else { return nil }
        return Key(title: title, artist: normalized(artist), album: normalized(album))
    }

    static func normalized(_ text: String?) -> String {
        guard let text else { return "" }
        return text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

extension LibraryModel {
    /// The index of what is on the iPod and in the queue. It is built once per
    /// sheet opening - on every redraw it would cost a pass
    /// over the whole library for every row.
    public func songIndex() -> SongIndex {
        SongIndex(tracks: library?.tracks ?? [], queued: changes.additions.map(\.draft))
    }
}
