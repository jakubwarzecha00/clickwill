#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension ITHMBImage {
    /// Bridge to the graphics layer. The core stays clean - this file is the only
    /// place that knows CoreGraphics exists at all.
    public func makeCGImage() -> CGImage? {
        guard width > 0, height > 0, let provider = CGDataProvider(data: Data(rgba) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
#endif

#if canImport(CoreGraphics)
extension ITHMBImage {
    /// Rasterizes the image to the given size: aspect fill with
    /// center cropping (artwork is square; other
    /// aspect ratios lose their edges instead of getting bars).
    public init(rendering image: CGImage, width: Int, height: Int) throws {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ITDBError.writeRefused(.inconsistent("can't create a \(width)x\(height) bitmap")) }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let drawn = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (CGFloat(width) - drawn.width) / 2, y: (CGFloat(height) - drawn.height) / 2)
        context.draw(image, in: CGRect(origin: origin, size: drawn))
        guard let data = context.data else { throw ITDBError.writeRefused(.inconsistent("the bitmap has no data")) }
        // Bitmap context memory starts at the top row - the same as
        // the ithmb file (a test checks orientation on an image with different halves).
        let bytes = UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: width * height * 4), count: width * height * 4)
        self.init(width: width, height: height, rgba: Array(bytes))
    }
}
#endif
