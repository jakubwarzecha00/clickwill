import Foundation

/// The cover stored inside a FLAC file.
///
/// FLAC keeps pictures in their own PICTURE metadata block, and AVFoundation reports only
/// the Vorbis comments, so the block is read here. The file is untrusted: every length is
/// checked against the bytes actually read, a picture that only links to an image is ignored,
/// and reading stops at the last metadata block or after `maximumBlocks`.
enum FLACPicture {
    /// More metadata blocks than any real file has; a file claiming more is not read further.
    static let maximumBlocks = 256

    private static let signature = Data("fLaC".utf8)
    private static let pictureBlock: UInt8 = 6
    /// "Cover (front)" in the FLAC picture types.
    private static let frontCover: UInt32 = 3
    /// The MIME type a PICTURE block uses when its data is a URL, not an image.
    private static let linkMIMEType = "-->"

    /// The front cover, or the first picture when no picture is marked as the front cover.
    /// `nil` for a file that is not FLAC or has no usable picture.
    static func cover(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard read(handle, count: 4).map(Data.init) == signature else { return nil }

        var firstPicture: Data?
        for _ in 0..<maximumBlocks {
            guard let header = read(handle, count: 4) else { break }
            let isLast = header[0] & 0x80 != 0
            let type = header[0] & 0x7F
            let length = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            if type == pictureBlock {
                guard let body = read(handle, count: length) else { break }
                if let picture = picture(in: body) {
                    if picture.type == frontCover { return picture.data }
                    if firstPicture == nil { firstPicture = picture.data }
                }
            } else {
                guard let offset = try? handle.offset(),
                      (try? handle.seek(toOffset: offset + UInt64(length))) != nil else { break }
            }
            if isLast { break }
        }
        return firstPicture
    }

    /// The picture type and image bytes of one PICTURE block body; `nil` when a length
    /// points past the block or the block only links to an image.
    static func picture(in body: [UInt8]) -> (type: UInt32, data: Data)? {
        var cursor = 0
        func number() -> UInt32? {
            guard body.count - cursor >= 4 else { return nil }
            defer { cursor += 4 }
            return body[cursor..<cursor + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func bytes(_ count: UInt32) -> ArraySlice<UInt8>? {
            guard Int(count) <= body.count - cursor else { return nil }
            defer { cursor += Int(count) }
            return body[cursor..<cursor + Int(count)]
        }
        guard let type = number(),
              let mimeLength = number(), let mime = bytes(mimeLength),
              String(decoding: mime, as: UTF8.self) != linkMIMEType,
              let descriptionLength = number(), bytes(descriptionLength) != nil,
              number() != nil, number() != nil, number() != nil, number() != nil,  // width, height, depth, colors
              let dataLength = number(), dataLength > 0, let data = bytes(dataLength)
        else { return nil }
        return (type, Data(data))
    }

    /// Exactly `count` bytes, or `nil` when the file ends sooner.
    private static func read(_ handle: FileHandle, count: Int) -> [UInt8]? {
        guard count > 0 else { return [] }
        guard let data = try? handle.read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}
