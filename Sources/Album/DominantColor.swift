import CoreGraphics
import SwiftUI

/// The artwork's dominant color for the album header background. The image is shrunk to 24x24,
/// quantized to 4 bits per channel, and the buckets are counted; we pick the one with the highest
/// product of area and saturation, so that gray backgrounds and white margins do not
/// win over the hue that really defines the artwork. Without such a bucket
/// the average color is returned.
enum DominantColor {
    static func of(_ image: CGImage) -> Color {
        let side = 24
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Color.gray }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return Color.gray }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var buckets: [Int: (count: Int, score: Int, r: Int, g: Int, b: Int)] = [:]
        var sumR = 0, sumG = 0, sumB = 0
        for i in 0..<(side * side) {
            let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
            sumR += r; sumG += g; sumB += b
            let saturation = max(r, g, b) - min(r, g, b)
            let brightness = max(r, g, b)
            // We reject almost-gray and almost-black - on a dark background they add nothing.
            guard saturation > 28, brightness > 40 else { continue }
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            // Score = area x saturation: the beige background of Paranoid has a larger
            // area than the pink, but pink is the color of this artwork.
            var bucket = buckets[key] ?? (0, 0, 0, 0, 0)
            bucket.count += 1; bucket.score += saturation; bucket.r += r; bucket.g += g; bucket.b += b
            buckets[key] = bucket
        }
        let total = side * side
        if let best = buckets.values.max(by: { $0.score < $1.score }), best.count >= total / 40 {
            return Color(red: Double(best.r) / Double(best.count) / 255,
                         green: Double(best.g) / Double(best.count) / 255,
                         blue: Double(best.b) / Double(best.count) / 255)
        }
        return Color(red: Double(sumR) / Double(total) / 255,
                     green: Double(sumG) / Double(total) / 255,
                     blue: Double(sumB) / Double(total) / 255)
    }
}
