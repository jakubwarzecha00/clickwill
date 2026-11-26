import AppKit
import SwiftUI

/// A palm silhouette shipped with the module: black on transparent, trunk standing on the
/// image's bottom edge. Both are public domain drawings from Openclipart:
/// - coconut: "Palm Tree", https://openclipart.org/detail/261353 (CC0)
/// - date: "Detailed Palm Tree Silhouette" by GDJ, https://openclipart.org/detail/317990
enum PalmSilhouette: String, CaseIterable {
    case coconut = "coconut-palm"
    case date = "date-palm"

    /// Read once; nil only if the file is missing from the bundle.
    @MainActor var image: NSImage? { Self.images[self] ?? nil }

    @MainActor private static let images: [PalmSilhouette: NSImage?] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, Bundle.module.image(forResource: $0.rawValue)) })
}

/// Palms standing on the bottom edge of the scene, at its sides, so the artwork in the
/// middle stays clear. The near ones are dark plum; the far ones paler, as if in haze. Each
/// sways a little in the wind, around the foot of its trunk.
struct PalmGrove: View {
    let size: CGSize
    let time: Double

    private enum Depth {
        case near, far

        var color: Color { self == .near ? ViceColors.nearPalm : ViceColors.farPalm }
        var opacity: Double { self == .near ? 0.96 : 0.85 }
        /// How far the palm leans each way, in degrees.
        var sway: Double { self == .near ? 0.6 : 0.4 }
    }

    /// One palm: which drawing, where its middle stands as a share of the width, its height
    /// as a share of the scene, whether it is mirrored, and how long one sway takes.
    private struct Palm {
        let silhouette: PalmSilhouette
        let x: CGFloat
        let height: CGFloat
        let mirrored: Bool
        let depth: Depth
        let period: Double
    }

    /// Far palms first, so the near ones stand in front of them.
    private static let palms = [
        Palm(silhouette: .date, x: 0.34, height: 0.6, mirrored: false, depth: .far, period: 9),
        Palm(silhouette: .date, x: 0.84, height: 0.52, mirrored: true, depth: .far, period: 11),
        Palm(silhouette: .coconut, x: 0.08, height: 0.98, mirrored: false, depth: .near, period: 7),
        Palm(silhouette: .coconut, x: 0.95, height: 0.92, mirrored: true, depth: .near, period: 8),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.palms.indices, id: \.self) { index in
                palm(Self.palms[index], phase: Double(index))
            }
        }
    }

    @ViewBuilder private func palm(_ palm: Palm, phase: Double) -> some View {
        if let image = palm.silhouette.image {
            let height = size.height * palm.height
            let width = height * image.size.width / max(image.size.height, 1)
            let lean = sin(time * 2 * .pi / palm.period + phase) * palm.depth.sway
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .foregroundStyle(palm.depth.color)
                .frame(width: width, height: height)
                .scaleEffect(x: palm.mirrored ? -1 : 1)
                .rotationEffect(.degrees(lean), anchor: .bottom)
                .opacity(palm.depth.opacity)
                .position(x: size.width * palm.x, y: size.height - height / 2)
        }
    }
}
