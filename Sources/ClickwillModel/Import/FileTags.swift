import Foundation
import AVFoundation

/// Tags written to an M4A file during conversion (ripping a disc). The file
/// with tags is then read by the regular import, so a disc goes the same way as
/// any other album: duplicate detection, artwork, the change queue.
public struct FileTags: Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var year: UInt32 = 0
    public var trackNumber: UInt32 = 0
    public var totalTracks: UInt32 = 0
    public var discNumber: UInt32 = 0
    public var totalDiscs: UInt32 = 0
    public var isCompilation = false
    public var cover: Data?

    public init(title: String) { self.title = title }

    func metadataItems() -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        func add(_ identifier: AVMetadataIdentifier, _ value: (any NSCopying & NSObjectProtocol)?, type: String? = nil) {
            guard let value else { return }
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value
            if let type { item.dataType = type }
            items.append(item)
        }
        func text(_ value: String?) -> NSString? {
            guard let value, !value.isEmpty else { return nil }
            return value as NSString
        }
        add(.iTunesMetadataSongName, text(title))
        add(.iTunesMetadataArtist, text(artist))
        add(.iTunesMetadataAlbum, text(album))
        add(.iTunesMetadataAlbumArtist, text(albumArtist))
        add(.iTunesMetadataUserGenre, text(genre))
        if year > 0 { add(.iTunesMetadataReleaseDate, String(year) as NSString) }
        // The number and total in the iTunes binary field: the number at bytes 2-3, the total at 4-5.
        if trackNumber > 0 {
            add(.iTunesMetadataTrackNumber, Self.pair(trackNumber, totalTracks, length: 8) as NSData,
                type: kCMMetadataBaseDataType_RawData as String)
        }
        if discNumber > 0 {
            add(.iTunesMetadataDiscNumber, Self.pair(discNumber, totalDiscs, length: 6) as NSData,
                type: kCMMetadataBaseDataType_RawData as String)
        }
        if isCompilation {
            add(.iTunesMetadataDiscCompilation, NSNumber(value: Int8(1)), type: kCMMetadataBaseDataType_SInt8 as String)
        }
        if let cover, !cover.isEmpty {
            let png = cover.starts(with: [0x89, 0x50, 0x4E, 0x47])
            add(.iTunesMetadataCoverArt, cover as NSData,
                type: (png ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String)
        }
        return items
    }

    static func pair(_ number: UInt32, _ total: UInt32, length: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        bytes[2] = UInt8((number >> 8) & 0xFF); bytes[3] = UInt8(number & 0xFF)
        bytes[4] = UInt8((total >> 8) & 0xFF); bytes[5] = UInt8(total & 0xFF)
        return Data(bytes)
    }
}
