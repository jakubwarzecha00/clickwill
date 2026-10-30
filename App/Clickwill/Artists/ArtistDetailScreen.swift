import SwiftUI
import ClickwillModel

/// Albums for a specific artist.
struct ArtistDetailScreen: View {
    @Environment(LibraryModel.self) private var model
    let artist: String
    let openAlbum: (AlbumCard) -> Void
    @State private var selection = Set<UInt32>()
    @State private var error: String?

    private var albums: [AlbumCard] {
        model.albums.filter { $0.displayArtist == artist }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(artist)
                .font(.system(size: 32, weight: .bold))
                .padding(.top, 20)
                .padding(.horizontal, 20)

            if albums.isEmpty {
                Spacer()
                Text("No albums found for this artist")
                    .font(.theme(.body))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220))], spacing: 20) {
                        ForEach(albums) { album in
                            AlbumCardView(album: album, open: openAlbum)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.stage)
        .alert("This change couldn't be made", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

/// A card showing an album with its cover.
private struct AlbumCardView: View {
    @Environment(LibraryModel.self) private var model
    let album: AlbumCard
    let open: (AlbumCard) -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 8) {
            AlbumCoverFace(album: album, size: 160)
                .frame(width: 160, height: 160)
                .clipped()
                .overlay(alignment: .topTrailing) { AlbumCoverBadge(album: album) }
                .overlay {
                    if hovered {
                        Rectangle()
                            .fill(.white.opacity(0.1))
                    }
                }
                .onHover { inside in hovered = inside }
                .onTapGesture(count: 2) { open(album) }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle)
                    .font(.theme(.row, weight: .medium))
                    .lineLimit(2)
                Text(album.displayArtist)
                    .font(.theme(.footnote))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 160, alignment: .leading)
        }
        .contextMenu {
            Button("Show Album") { open(album) }
        }
        .task(id: album.artworkTrackID) { await model.ensureArtwork(for: album.artworkTrackID) }
    }
}
