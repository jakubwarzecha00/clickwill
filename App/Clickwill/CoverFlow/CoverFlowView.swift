import SwiftUI
import AppKit
import ClickwillModel

/// Cover Flow following the design: 250 pt artwork, neighbors tilted by 60-64 degrees
/// and shifted by 186/272/352 pt, a 120 pt reflection masked to transparency,
/// a 900 px perspective with the vanishing point at 42% of the height. In a low or narrow
/// window the whole scene shrinks in the same proportion.
struct CoverFlowScreen: View {
    @Environment(LibraryModel.self) private var model
    @Binding var centered: Int
    let open: (AlbumCard) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CoverFlowStage(albums: model.coverFlowDisplay, centered: $centered, open: open)
            scrubber
        }
        .background(Theme.flowTop)
        .onChange(of: model.coverFlowDisplay.count) { _, count in clamp(to: count) }
        .onAppear { clamp(to: model.coverFlowDisplay.count) }
    }

    /// After deleting albums from another screen the index may point beyond the list.
    private func clamp(to count: Int) {
        centered = min(max(0, centered), max(0, count - 1))
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            PositionSlider(index: $centered, count: model.coverFlowDisplay.count, label: "Album in Cover Flow")
            PositionCounter(index: centered, count: model.coverFlowDisplay.count)
        }
        .padding(EdgeInsets(top: 0, leading: 30, bottom: 26, trailing: 30))
    }
}

struct CoverFlowStage: View {
    @Environment(LibraryModel.self) private var model
    let albums: [AlbumCard]
    @Binding var centered: Int
    let open: (AlbumCard) -> Void

    private let fullCoverSize: CGFloat = 250
    private let visibleEachSide = 6
    @FocusState private var focused: Bool

    /// 250 pt artwork; in a smaller window as much as fits, and the rest of the scene
    /// (the neighbors' spacing, the floor, the caption) scales together with it.
    private func coverSize(in size: CGSize) -> CGFloat {
        min(fullCoverSize, size.width * 0.55, size.height * 0.42)
    }

    var body: some View {
        GeometryReader { geo in
            let coverSize = coverSize(in: geo.size)
            let k = coverSize / fullCoverSize
            ZStack {
                LinearGradient(colors: [Theme.flowTop, Theme.flowBottom], startPoint: .top, endPoint: .bottom)
                // The floor starts 90 pt below the middle.
                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.size.height / 2 + 90 * k)
                    LinearGradient(colors: [Theme.floorTop, Theme.floorBottom], startPoint: .top, endPoint: .bottom)
                }
                // The bottom of the artwork lies on the floor line (middle + 90 pt), the reflection below.
                ForEach(visibleIndices, id: \.self) { index in
                    let distance = index - centered
                    CoverTile(album: albums[index], size: coverSize, distance: distance)
                        .position(x: geo.size.width / 2 + offset(for: distance) * k,
                                  y: geo.size.height / 2 + (90 - (distance == 0 ? 10 : 0)) * k - coverSize / 2)
                        .zIndex(Double(100 - abs(distance)))
                        // For VoiceOver and for interface tests: the artwork is a button with a title.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(albums[index].displayTitle)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier(distance == 0 ? "coverflow.center" : "coverflow.side")
                        .onTapGesture(count: 2) { if distance == 0 { open(albums[index]) } }
                        .onTapGesture { withAnimation(.spring(duration: 0.35, bounce: 0.15)) { centered = index } }
                }
                // The caption is measured from the same floor line as the artwork, not
                // from the window edge - that way it stays with the artwork regardless
                // of the scene height.
                caption
                    .position(x: geo.size.width / 2,
                              y: geo.size.height / 2 + (90 - 10 - 40) * k - coverSize)
                    .zIndex(200)
            }
            .clipped()
            .overlay { ScrollWheelCatcher { delta in step(delta) } }
            // ContentView handles the keys (it knows the active screen); the scene only
            // holds focus, so that keyboard events reach SwiftUI at all.
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
        }
    }

    private func move(to index: Int) {
        guard !albums.isEmpty else { return }
        let target = min(albums.count - 1, max(0, index))
        guard target != centered else { return }
        withAnimation(.spring(duration: 0.32, bounce: 0.12)) { centered = target }
    }


    private var current: AlbumCard? {
        albums.indices.contains(centered) ? albums[centered] : nil
    }

    private var caption: some View {
        VStack(spacing: 3) {
            Text(current?.displayTitle ?? "").font(.theme(.title3, weight: .semibold))
            Text(current?.displayArtist ?? "").font(.theme(.row)).foregroundStyle(.white.opacity(0.62))
            // A new album from the queue: visible right away, but not on the iPod yet.
            if current?.isPending == true {
                Label("Added on Write to iPod", systemImage: "clock")
                    .font(.theme(.footnote, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(.white.opacity(0.12), in: .capsule)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private var visibleIndices: [Int] {
        guard !albums.isEmpty else { return [] }
        let safe = min(max(0, centered), albums.count - 1)
        let lower = max(0, safe - visibleEachSide)
        let upper = min(albums.count - 1, safe + visibleEachSide)
        return lower <= upper ? Array(lower...upper) : []
    }

    private func step(_ delta: Int) { move(to: centered + delta) }

    /// 186 / 272 / 352 pt for the first three neighbors, then 60 pt each.
    private func offset(for distance: Int) -> CGFloat {
        let d = abs(distance)
        guard d > 0 else { return 0 }
        let base: [CGFloat] = [0, 186, 272, 352]
        let x = d < base.count ? base[d] : base.last! + CGFloat(d - 3) * 60
        return distance < 0 ? -x : x
    }
}

struct CoverTile: View {
    @Environment(LibraryModel.self) private var model
    let album: AlbumCard
    let size: CGFloat
    let distance: Int
    private var d: Int { abs(distance) }
    private var angle: Double { d == 0 ? 0 : min(64, 60 + Double(d - 1) * 2) * (distance < 0 ? 1 : -1) }
    private var scale: CGFloat { d == 0 ? 1 : max(0.78, 0.93 - CGFloat(d - 1) * 0.045) }
    private var shade: Double { d == 0 ? 0 : min(0.52, 0.34 + Double(d - 1) * 0.09) }
    /// 130 and 120 pt for 250 pt artwork.
    private var reflectionHeight: CGFloat { size * (d == 0 ? 0.52 : 0.48) }
    private var reflectionOpacity: Double { d == 0 ? 0.42 : max(0.3, 0.34 - Double(d - 1) * 0.02) }

    var body: some View {
        VStack(spacing: 0) {
            face
                .frame(width: size, height: size)
                .overlay(alignment: .leading) { if distance != 0 { shading } }
                .overlay(alignment: .topTrailing) { AlbumCoverBadge(album: album) }
                .shadow(color: .black.opacity(d == 0 ? 0.72 : 0.6), radius: d == 0 ? 26 : 17, y: d == 0 ? 26 : 18)
            reflection
        }
        // `position` sets the center of the whole tile (artwork + reflection); we shift
        // by half the reflection, so that the center of the artwork lands on the given point.
        .offset(y: reflectionHeight / 2)
        .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: CGFloat(size) / CGFloat(size + reflectionHeight)))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0),
                          anchor: UnitPoint(x: 0.5, y: CGFloat(size / 2) / CGFloat(size + reflectionHeight)),
                          perspective: 0.42)
        .task(id: album.artworkTrackID) { await model.ensureArtwork(for: album.artworkTrackID) }
    }

    private var face: some View { AlbumCoverFace(album: album, size: size) }

    private var shading: some View {
        LinearGradient(
            colors: distance < 0 ? [.black.opacity(shade), .black.opacity(0.04)] : [.black.opacity(0.04), .black.opacity(shade)],
            startPoint: .leading, endPoint: .trailing)
    }

    private var reflection: some View {
        face
            .frame(width: size, height: size)
            .scaleEffect(y: -1)
            .frame(width: size, height: reflectionHeight, alignment: .top)
            .clipped()
            .mask(LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom))
            .opacity(reflectionOpacity)
    }
}
