import SwiftUI
import ClickwillModel

/// Album artwork, and without it a placeholder with a note and the title - the same in Cover
/// Flow and on the Albums wheel. Decoding is requested by the view that shows it
/// (`LibraryModel.ensureArtwork`) - once, not on every redraw.
public struct AlbumCoverFace: View {
    @Environment(LibraryModel.self) private var model
    public let album: AlbumCard
    public let size: CGFloat

    public init(album: AlbumCard, size: CGFloat) {
        self.album = album
        self.size = size
    }
    private var image: CGImage? { model.artwork(for: album.artworkTrackID) }

    public var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(Theme.card)
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: size * 0.136, weight: .light)).foregroundStyle(Theme.f3)
                    Text(album.displayTitle).font(.theme(.row, weight: .semibold)).foregroundStyle(Theme.f2)
                        .multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 18)
                }
            }
        }
    }
}

/// A badge in the corner of the artwork: the album is waiting to be written or has entries without a file.
public struct AlbumCoverBadge: View {
    public let album: AlbumCard

    public init(album: AlbumCard) { self.album = album }

    public var body: some View {
        if album.isPending {
            Image(systemName: "clock").font(.symbol(.badge, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(9)
                .help("Not on the iPod yet. Added when you choose Write to iPod.")
        } else if album.missingFiles > 0 {
            Image(systemName: "exclamationmark").font(.symbol(.small, weight: .black)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Theme.warn, in: Circle())
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(9)
                .help("\(album.missingFiles) entries without a file. They skip on the iPod.")
        }
    }
}
