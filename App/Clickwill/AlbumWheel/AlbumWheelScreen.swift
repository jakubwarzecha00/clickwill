import SwiftUI
import ClickwillModel

/// The Albums tab: the iPod's Albums menu in the same order (`albumsDisplay`),
/// laid out on a wheel. The selected album stands in the middle, pushed out the farthest and bright;
/// the rest goes down the arc up and down, smaller, dimmed and slightly
/// tilted. The design follows an approved mockup.
///
/// The middle of the wheel is the selection, not a cursor: the mouse wheel, the trackpad, the arrows
/// (handled by `ContentView`) and the slider at the side turn it. Clicking an album turns it
/// to the middle, double-clicking the middle one - as in Cover Flow - opens the album.
struct AlbumWheelScreen: View {
    @Environment(LibraryModel.self) private var model
    @Binding var centered: Int
    let open: (AlbumCard) -> Void
    /// The letter brighter for a moment after each jump.
    @State private var letterLit = false
    /// The album the column on the right talks about - only once the wheel stops.
    /// In motion the column fades, so nothing on the right flickers.
    @State private var settled: Int?
    @State private var hovered: Int?
    @FocusState private var focused: Bool

    var body: some View {
        let albums = model.albumsDisplay
        GeometryReader { geo in
            let wheel = WheelGeometry(size: geo.size)
            ZStack(alignment: .topLeading) {
                wheelLayer(albums: albums, wheel: wheel)
                    // The mouse wheel only over the wheel: an AppKit overlay over the slider
                    // took its clicks, even though it does not accept them itself.
                    .overlay { ScrollWheelCatcher(vertical: true) { delta in move(to: centered + delta) } }
                slider(count: albums.count, height: geo.size.height)
                    .position(x: geo.size.width - 21, y: geo.size.height / 2 - 11)
                    .zIndex(300)
                if Self.showsInfo(in: geo.size), let settled, albums.indices.contains(settled) {
                    AlbumInfoColumn(album: albums[settled], open: open)
                        .position(x: geo.size.width - 40 - AlbumInfoColumn.width / 2, y: geo.size.height / 2)
                        .transition(.opacity)
                        .zIndex(250)
                }
                PositionCounter(index: centered, count: albums.count)
                    .position(x: geo.size.width - 46, y: geo.size.height - 22)
                    .zIndex(300)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
        }
        .background(Theme.stage)
        .onChange(of: albums.count) { _, count in clamp(to: count) }
        .onAppear { clamp(to: albums.count) }
        .task(id: centered) {
            withAnimation(.easeOut(duration: 0.12)) { settled = nil }
            letterLit = true
            // The rotation spring takes about 0.32 s.
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 0.35)) { settled = centered }
            try? await Task.sleep(for: .milliseconds(350))
            letterLit = false
        }
    }

    /// The albums on the wheel and the letter of the current album - everything except the slider.
    private func wheelLayer(albums: [AlbumCard], wheel: WheelGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleIndices(count: albums.count), id: \.self) { index in
                let distance = index - centered
                WheelItem(album: albums[index], distance: Double(distance), wheel: wheel,
                          hovered: hovered == index && distance != 0,
                          showsPendingNote: !Self.showsInfo(in: wheel.size))
                    .zIndex(Double(100 - abs(distance)))
                    .onHover { inside in
                        if inside { hovered = index } else if hovered == index { hovered = nil }
                    }
                    .onTapGesture(count: 2) { if distance == 0 { open(albums[index]) } }
                    .onTapGesture { move(to: index) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(albums[index].displayTitle), \(albums[index].displayArtist)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier(distance == 0 ? "albums.center" : "albums.side")
            }
            if albums.indices.contains(centered) {
                Text(model.menuLetter(of: albums[centered]))
                    .font(.system(size: 22 * wheel.scale, weight: .medium))
                    .foregroundStyle(.white.opacity(letterLit ? 0.6 : 0.28))
                    .animation(letterLit ? .easeOut(duration: 0.12) : .easeOut(duration: 0.5), value: letterLit)
                    .position(x: wheel.letterX, y: wheel.size.height / 2)
                    .accessibilityHidden(true)
                    .zIndex(200)
            }
        }
        .frame(width: wheel.size.width, height: wheel.size.height, alignment: .topLeading)
    }

    /// The column on the right only in a wide window - in a narrow one the wheel takes precedence.
    static func showsInfo(in size: CGSize) -> Bool { size.width >= 760 }

    /// A vertical position slider from the top of the scene to the counter.
    private func slider(count: Int, height: CGFloat) -> some View {
        VerticalPositionSlider(index: $centered,
                               count: count, label: "Album in Albums")
            .frame(width: 22, height: max(40, height - 66))
    }

    /// Three albums in each direction are visible on the wheel; one more, so that the one
    /// coming in from behind the edge is already there when the wheel turns.
    private func visibleIndices(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let safe = min(max(0, centered), count - 1)
        return Array(max(0, safe - 4)...min(count - 1, safe + 4))
    }

    private func move(to index: Int) {
        let count = model.albumsDisplay.count
        guard count > 0 else { return }
        let target = min(count - 1, max(0, index))
        guard target != centered else { return }
        withAnimation(.spring(duration: 0.32, bounce: 0.12)) { centered = target }
    }

    /// After deleting an album or clearing the queue the index may point beyond the list.
    private func clamp(to count: Int) {
        centered = min(max(0, centered), max(0, count - 1))
    }
}

/// The wheel's dimensions. The layout of the approved mockup (a 900 x 560 pt scene: artwork
/// 106 pt, radius 246 pt, the middle pushed out by 150 pt, an 18 degree tilt
/// at 60 degrees) scaled as a whole
/// to the scene - like Cover Flow. Artwork, text and spacing grow together,
/// so the proportions stay the approved ones.
struct WheelGeometry {
    let size: CGSize
    /// The scale relative to the mockup's scene.
    let scale: CGFloat

    static let reference = CGSize(width: 900, height: 560)
    static let step = 30.0 * .pi / 180
    /// Beyond this an album hides behind the edge of the wheel.
    static let limit = 84.0 * .pi / 180
    static let tilt = 18.0

    init(size: CGSize) {
        self.size = size
        scale = max(0.7, min(size.height / Self.reference.height, size.width / Self.reference.width))
    }

    var cover: CGFloat { 106.4 * scale }
    /// The wheel's vertical radius.
    var radius: CGFloat { 246 * scale }
    /// How far the middle sticks out to the right beyond the albums at the edge.
    var reach: CGFloat { 150 * scale }
    var inset: CGFloat { 26 * scale }
    var gap: CGFloat { 18 * scale }

    /// The left edge of the artwork of the album in the middle of the wheel.
    var centerX: CGFloat { inset + reach * 0.58 }
    /// The letter stands halfway between the left edge of the scene and that artwork.
    var letterX: CGFloat { centerX / 2 }
}

/// One album on the wheel. `distance` is the distance from the middle in albums -
/// fractional during rotation (`Animatable`), so the album travels along
/// the arc, and the brightness and title color change smoothly, not in a jump.
private struct WheelItem: View, Animatable {
    @Environment(LibraryModel.self) private var model
    let album: AlbumCard
    var distance: Double
    let wheel: WheelGeometry
    let hovered: Bool
    /// The note "Added on Write to iPod" under an album from the queue - when the column
    /// on the right does not say it.
    let showsPendingNote: Bool

    nonisolated var animatableData: Double {
        get { distance }
        set { distance = newValue }
    }

    var body: some View {
        let angle = distance * WheelGeometry.step
        let c = cos(angle), s = sin(angle)
        // Only the middle is really bright - the exponents from the mockup.
        let lit = pow(c, 14)
        let lift = hovered ? 0.12 : 0
        let cover = wheel.cover
        HStack(spacing: wheel.gap) {
            AlbumCoverFace(album: album, size: cover)
                .frame(width: cover, height: cover)
                .clipped()
                .overlay(Color.black.opacity(max(0, 1 - (0.34 + 0.66 * pow(c, 6)) - lift)))
                .overlay(alignment: .topTrailing) { AlbumCoverBadge(album: album) }
                .shadow(color: .black.opacity(0.6), radius: 12, y: 7)
            VStack(alignment: .leading, spacing: 1) {
                // A long title of the selected album scrolls instead of being cut off.
                MarqueeText(text: album.displayTitle, active: abs(distance) < 0.01, speed: 32 * wheel.scale)
                    .font(.system(size: cover * 0.24, weight: .medium))
                    .foregroundStyle(.white.opacity(min(1, 0.42 + 0.58 * lit + lift)))
                MarqueeText(text: album.displayArtist, active: abs(distance) < 0.01, speed: 32 * wheel.scale)
                    .font(.system(size: cover * 0.135))
                    .foregroundStyle(Color(white: 0.92).opacity(min(1, 0.3 + 0.32 * lit + lift * 0.6)))
                if album.isPending, showsPendingNote {
                    Label("Added on Write to iPod", systemImage: "clock")
                        .font(.theme(.footnote, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: .capsule)
                        .padding(.top, 7)
                        .opacity(max(0, 1 - abs(distance) * 2))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: 260 * wheel.scale, alignment: .leading)
        }
        .frame(height: cover)
        // The selected album clearly larger than the rest: the neighbor about 78%,
        // further ones about 53%. The mockup had 0.56 + 0.44 cos - the neighbor almost the same.
        .scaleEffect(0.5 + 0.5 * pow(c, 4), anchor: .leading)
        .rotation3DEffect(.degrees(-WheelGeometry.tilt * angle / (.pi / 3)), axis: (x: 1, y: 0, z: 0),
                          anchor: .leading, perspective: 0.5)
        .opacity(min(1, max(0, (WheelGeometry.limit - abs(angle)) / 0.32)))
        .offset(x: wheel.inset + wheel.reach * c - wheel.reach * 0.42,
                y: wheel.size.height / 2 + wheel.radius * s - cover / 2)
        .task(id: album.artworkTrackID) { await model.ensureArtwork(for: album.artworkTrackID) }
    }
}
