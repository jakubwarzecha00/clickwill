import SwiftUI
import CoreImage

/// The blurred artwork under the album view, computed once per artwork. A small source
/// (160 px) blurred in Core Image looks the same after enlarging as a 30 pt blur
/// on the full image, and costs a fraction.
@MainActor
enum BackdropBlur {
    private static var cache: [UInt64: CGImage] = [:]
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func image(_ source: CGImage, id: UInt64?) -> CGImage {
        if let id, let cached = cache[id] { return cached }
        let input = CIImage(cgImage: source)
        let scale = 160 / max(input.extent.width, input.extent.height, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 6])
            .cropped(to: small.extent)
        let result = context.createCGImage(blurred, from: small.extent) ?? source
        if cache.count > 64 { cache.removeAll() }
        if let id { cache[id] = result }
        return result
    }
}

/// The album view background: the artwork centered, filling edge to edge
/// (cropped), blurred and darkened. Shared by an album on the iPod
/// and an album waiting to be written, so both look the same.
struct AlbumBackdrop: View {
    let image: CGImage
    let id: UInt64?

    var body: some View {
        GeometryReader { geo in
            // Blurred once, not in every frame: when the inspector opens the view
            // changes width, and a live blur stuttered.
            Image(decorative: BackdropBlur.image(image, id: id), scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                // Enlarging hides the blurred edges outside the frame.
                .frame(width: geo.size.width * 1.2, height: geo.size.height * 1.2)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .overlay(Theme.bg.opacity(0.5))
                .overlay(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Theme.bg.opacity(0.75), location: 0.42),
                    .init(color: Theme.bg.opacity(0.88), location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .clipped()
        }
        // The enlarged image sticks out beyond the frame - without this it would catch clicks
        // in the toolbar above it (the back button).
        .allowsHitTesting(false)
    }
}
