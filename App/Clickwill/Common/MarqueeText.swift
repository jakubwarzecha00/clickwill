import SwiftUI

/// Single-line text that - when it does not fit and is `active` -
/// scrolls to the left like a title in streaming services: it stands still for 0.8 s,
/// moves at a steady pace until a copy comes back to the starting place, and
/// starts over. The edges fade softly. Inactive or short - plain text with
/// an ellipsis. It takes the font and color from the environment.
struct MarqueeText: View {
    let text: String
    var active = true
    /// Points per second.
    var speed: CGFloat = 32
    @State private var fullWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()

    private static let pause = 0.8
    private static let gap: CGFloat = 40
    private static let fade: CGFloat = 14

    private var scrolls: Bool { active && fullWidth > boxWidth + 0.5 }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
            .background(alignment: .leading) {
                Text(text).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { fullWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if scrolls {
                    TimelineView(.animation) { context in
                        let shift = offset(at: context.date)
                        HStack(spacing: Self.gap) {
                            Text(text).fixedSize()
                            Text(text).fixedSize()
                        }
                        .offset(x: -shift)
                        .frame(width: boxWidth, alignment: .leading)
                        .clipped()
                        .mask(edges(leading: shift > 0))
                    }
                }
            }
            .onChange(of: scrolls) { _, now in if now { start = Date() } }
            .accessibilityLabel(text)
    }

    /// The offset at moment `date`: a pause, then travel by the length of the text and the gap.
    private func offset(at date: Date) -> CGFloat {
        let distance = fullWidth + Self.gap
        let cycle = Self.pause + Double(distance / speed)
        let t = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        return t < Self.pause ? 0 : CGFloat(t - Self.pause) * speed
    }

    private func edges(leading: Bool) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fade)
        }
    }
}
