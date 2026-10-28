import Foundation

/// A decoded image - raw RGBA pixels, with no dependency on graphics frameworks.
public struct ITHMBImage: Sendable {
    public let width: Int
    public let height: Int
    /// `width * height * 4` bytes, in R, G, B, A order.
    public let rgba: [UInt8]
}

/// `.ithmb` files are plain arrays of images with a fixed slot size and
/// no header of their own. Pixels are RGB565 little-endian - confirmed
/// by decoding real artwork and comparing the colors with the original.
public enum ITHMB {

    /// Loads one artwork variant. Reads only the slice it needs -
    /// `F1060_1.ithmb` can be 27 MB.
    public static func read(_ variant: ArtworkVariant, in paths: IPodPaths) throws -> ITHMBImage {
        let url = try variant.url(in: paths)
        guard variant.hasSaneBounds else {
            throw ITDBError.readOutOfBounds(offset: Int(variant.byteOffset), size: Int(variant.byteCount))
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ITDBError.pathMissing(url)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: UInt64(variant.byteOffset))
        guard let data = try handle.read(upToCount: Int(variant.byteCount)),
              data.count == Int(variant.byteCount)
        else {
            throw ITDBError.readOutOfBounds(offset: Int(variant.byteOffset), size: Int(variant.byteCount))
        }

        return decodeRGB565(
            [UInt8](data),
            width: Int(variant.width),
            height: Int(variant.height),
            pixelStride: variant.pixelStride
        )
    }

    /// RGB565 little-endian -> RGBA8.
    ///
    /// `pixelStride` is the row width in the file, which can be larger than the image
    /// width - format 1061 keeps a 55x55 image in a slot with a 56-pixel stride.
    public static func decodeRGB565(
        _ raw: [UInt8], width: Int, height: Int, pixelStride: Int
    ) -> ITHMBImage {
        let stride = max(pixelStride, width)
        var rgba = [UInt8](repeating: 255, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let source = (y * stride + x) * 2
                guard source + 1 < raw.count else { continue }
                let value = UInt16(raw[source]) | UInt16(raw[source + 1]) << 8
                let destination = (y * width + x) * 4
                // 5 bits of red, 6 of green, 5 of blue, stretched to a full byte.
                // The math runs on Int - in UInt8 the product 31 * 255 would not fit.
                rgba[destination] = UInt8(Int((value >> 11) & 0x1F) * 255 / 31)
                rgba[destination + 1] = UInt8(Int((value >> 5) & 0x3F) * 255 / 63)
                rgba[destination + 2] = UInt8(Int(value & 0x1F) * 255 / 31)
                rgba[destination + 3] = 255
            }
        }
        return ITHMBImage(width: width, height: height, rgba: rgba)
    }

    /// RGBA8 -> RGB565 little-endian, padded to the given row stride.
    /// Needed when replacing artwork.
    public static func encodeRGB565(
        _ image: ITHMBImage, pixelStride: Int, slotSize: Int
    ) -> [UInt8] {
        let stride = max(pixelStride, image.width)
        var raw = [UInt8](repeating: 0, count: slotSize)

        for y in 0..<image.height {
            for x in 0..<image.width {
                let source = (y * image.width + x) * 4
                let red = UInt16(image.rgba[source]) >> 3
                let green = UInt16(image.rgba[source + 1]) >> 2
                let blue = UInt16(image.rgba[source + 2]) >> 3
                let value = red << 11 | green << 5 | blue
                let destination = (y * stride + x) * 2
                guard destination + 1 < raw.count else { continue }
                raw[destination] = UInt8(value & 0xFF)
                raw[destination + 1] = UInt8(value >> 8)
            }
        }
        return raw
    }
}
