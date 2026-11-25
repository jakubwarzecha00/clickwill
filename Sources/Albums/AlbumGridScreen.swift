import SwiftUI
import ClickwillModel
import ClickwillShared

/// The Albums tab as a grid: the iPod's Albums menu in the same order as the wheel
/// (`albumsDisplay`), artwork with the title and artist under it. A click opens the album;
/// the arrows move the selection (`AlbumsState.handle`) and Return opens it.
struct AlbumGridScreen: View {
    @Environment(LibraryModel.self) private var model
    @Binding var selected: Int
    @Binding var columns: Int
    let open: @MainActor (AlbumCard) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let albums = model.albumsDisplay
        GeometryReader { geo in
            let grid = GridGeometry(width: geo.size.width)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(grid.cell), spacing: grid.spacing, alignment: .top),
                                             count: grid.columns),
                              alignment: .leading, spacing: GridGeometry.rowSpacing) {
                        ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                            GridCell(album: album, size: grid.cell, isSelected: index == selected)
                                .id(album.id)
                                .contentShape(.rect)
                                .onTapGesture {
                                    selected = index
                                    open(album)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(album.displayTitle), \(album.displayArtist)")
                                .accessibilityAddTraits(index == selected ? [.isButton, .isSelected] : .isButton)
                                .accessibilityIdentifier("albums.grid.item")
                        }
                    }
                    .padding(.horizontal, GridGeometry.margin)
                    .padding(.vertical, GridGeometry.margin - 4)
                }
                .onAppear {
                    columns = grid.columns
                    clamp(to: albums.count)
                    if albums.indices.contains(selected) { proxy.scrollTo(albums[selected].id, anchor: .center) }
                }
                .onChange(of: grid.columns) { _, count in columns = count }
                // Without an anchor the grid scrolls only as far as the selection needs.
                .onChange(of: selected) { _, index in
                    guard albums.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(albums[index].id) }
                }
            }
        }
        .background(Theme.stage)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onChange(of: albums.count) { _, count in clamp(to: count) }
    }

    /// After deleting an album the index may point beyond the list.
    private func clamp(to count: Int) {
        selected = min(max(0, selected), max(0, count - 1))
    }
}

/// As many columns as fit cells of at least `minCell`; the cells then grow to fill the row.
struct GridGeometry {
    static let minCell: CGFloat = 160
    static let spacing: CGFloat = 26
    static let rowSpacing: CGFloat = 24
    static let margin: CGFloat = 32

    let columns: Int
    let cell: CGFloat
    var spacing: CGFloat { Self.spacing }

    init(width: CGFloat) {
        let available = max(Self.minCell, width - 2 * Self.margin)
        columns = max(1, Int((available + Self.spacing) / (Self.minCell + Self.spacing)))
        cell = ((available - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
    }
}

private struct GridCell: View {
    @Environment(LibraryModel.self) private var model
    let album: AlbumCard
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            AlbumCoverFace(album: album, size: size)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 5))
                .overlay(alignment: .topTrailing) { AlbumCoverBadge(album: album) }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, lineWidth: 3).padding(-4)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                .padding(.bottom, 6)
            Text(album.displayTitle)
                .font(.theme(.row, weight: .medium))
                .foregroundStyle(Theme.fg)
            Text(album.displayArtist)
                .font(.theme(.callout))
                .foregroundStyle(Theme.f2)
        }
        .lineLimit(1)
        .frame(width: size, alignment: .leading)
        .task(id: album.artworkTrackID) { await model.ensureArtwork(for: album.artworkTrackID) }
    }
}
