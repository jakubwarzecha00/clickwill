import SwiftUI

/// The Vice sky as one unbroken gradient: indigo at the top through lavender and mauve to a
/// rose horizon, then rose water darkening to plum at the bottom edge.
enum SunsetSky {
    /// The stops above the horizon are shares of the sky and the ones below shares of the
    /// floor, so the colors keep their places whatever the scene's height.
    /// - Parameter horizon: where the floor begins, as a share of the height.
    static func stops(horizon: CGFloat) -> [Gradient.Stop] {
        let h = min(max(horizon, 0.05), 1)
        return [
            .init(color: ViceColors.indigo, location: 0),
            .init(color: ViceColors.lavender, location: h * 0.35),
            .init(color: ViceColors.mauve, location: h * 0.65),
            .init(color: ViceColors.blush, location: h * 0.88),
            .init(color: ViceColors.horizon, location: h),
            .init(color: ViceColors.water, location: h + (1 - h) * 0.3),
            .init(color: ViceColors.plum, location: 1),
        ]
    }
}
