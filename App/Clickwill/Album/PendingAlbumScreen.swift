import SwiftUI
import ClickwillModel

/// A new album waiting in the add queue. It is not on the iPod
/// yet, so there is no editing, ordering or playback from the iPod here -
/// only what will reach the device on "Write to iPod", and a way to withdraw it.
struct PendingAlbumScreen: View {
    @Environment(LibraryModel.self) private var model
    let album: AlbumCard
    let onClose: () -> Void

    private var pending: PendingAlbum? { model.pendingAlbum(id: album.id) }
    private var card: AlbumCard { pending?.card ?? album }
    private var image: CGImage? { model.artwork(for: card.artworkTrackID) }
    private var tint: Color { image.map(DominantColor.of) ?? Theme.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                notice
                columnTitles
                ForEach(pending?.additions ?? []) { song in
                    row(song)
                }
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The same background as the album view on the iPod - both views alike.
        .background { if let image { AlbumBackdrop(image: image, id: card.artworkTrackID) } }
        .background(LinearGradient(colors: [tint.opacity(0.42), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCorner))
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 4, trailing: 10))
        .background(Theme.stage)
        // The last song withdrawn or the album written - there is nothing to show.
        .onChange(of: pending == nil) { _, gone in if gone { onClose() } }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 26) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack { Theme.card; Image(systemName: "music.note").font(.symbol(.placeholder, weight: .light)).foregroundStyle(Theme.f3) }
                }
            }
            .frame(width: 250, height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.34), radius: 11, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Text(card.displayTitle).font(.theme(.largeTitle, weight: .bold)).lineLimit(2)
                Text(card.displayArtist).font(.theme(.title2, weight: .medium)).foregroundStyle(Theme.accent)
                Text(meta).font(.theme(.row)).foregroundStyle(Theme.f2).monospacedDigit()
                HStack(spacing: 9) {
                    Label("Added on Write to iPod", systemImage: "clock")
                        .font(.theme(.body, weight: .medium)).foregroundStyle(Theme.f2)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Theme.row, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.glassBorder, lineWidth: 0.5))
                    Button {
                        if let pending { model.removeQueuedAlbum(pending) }
                    } label: {
                        Label("Don't Add This Album", systemImage: "minus.circle")
                            .font(.theme(.body, weight: .medium)).glassChip(selected: false)
                    }
                    .chipButton(selected: false)
                    .help("Takes the album out of the pending changes. Your files on the Mac stay where they are.")
                    Spacer()
                }
                .padding(.top, 6)
            }
            .padding(.bottom, 4)
        }
        .padding(EdgeInsets(top: 26, leading: 32, bottom: 16, trailing: 32))
    }

    private var notice: some View {
        Text(image == nil
             ? "This album isn't on your iPod yet. It goes there when you choose Write to iPod."
             : "This album isn't on your iPod yet. It goes there, with its cover, when you choose Write to iPod.")
            .font(.theme(.body)).foregroundStyle(Theme.f2)
            .padding(EdgeInsets(top: 0, leading: 32, bottom: 14, trailing: 32))
    }

    private var meta: String {
        var parts: [String] = []
        if let genre = card.genre, !genre.isEmpty { parts.append(genre) }
        if let year = card.year { parts.append(String(year)) }
        parts.append("\(card.trackCount) song\(card.trackCount == 1 ? "" : "s")")
        parts.append(card.duration.minutesLabel)
        return parts.joined(separator: " · ")
    }

    private var columnTitles: some View {
        HStack(spacing: TrackColumns.spacing) {
            Text("#").frame(width: TrackColumns.number, alignment: .trailing)
            Text("Title").frame(maxWidth: .infinity, alignment: .leading)
            Text("Time").frame(width: TrackColumns.time, alignment: .trailing)
            Spacer().frame(width: TrackColumns.menu)
        }
        // Like the column header in the album view: the same typeface, color and line below.
        .font(.theme(.caption)).foregroundStyle(Theme.f2)
        .padding(EdgeInsets(top: 0, leading: TrackColumns.inset, bottom: 6, trailing: TrackColumns.inset))
        .overlay(alignment: .bottom) { Theme.sep.frame(height: 0.5) }
        // 24 as in the album plus the 8 margin that List adds there.
        .padding(.horizontal, 32)
        .padding(.bottom, 4)
    }

    private func row(_ song: PendingAddition) -> some View {
        HStack(spacing: TrackColumns.spacing) {
            Text(song.draft.trackNumber > 0 ? "\(song.draft.trackNumber)" : "")
                .font(.theme(.row).monospacedDigit()).foregroundStyle(Theme.f3)
                .frame(width: TrackColumns.number, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.draft.title).font(.theme(.rowLarge)).lineLimit(1)
                HStack(spacing: 6) {
                    if let artist = song.draft.artist, !artist.isEmpty {
                        Text(artist).foregroundStyle(Theme.f2)
                    }
                    Text(song.formatLabel).foregroundStyle(Theme.f3)
                    if let target = song.target {
                        Text("Converted to \(target.label)").foregroundStyle(.orange)
                    }
                }
                .font(.theme(.footnote)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text((TimeInterval(song.draft.durationMilliseconds) / 1000).clockLabel)
                .font(.theme(.row).monospacedDigit()).foregroundStyle(Theme.f2)
                .frame(width: TrackColumns.time, alignment: .trailing)
            Button { model.removeQueuedAddition(song.id) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.f3)
            }
            .buttonStyle(.plain)
            .frame(width: TrackColumns.menu)
            .help("Don't add this song")
            .accessibilityLabel("Don't add \(song.draft.title)")
        }
        // Like a row in the album view: the same spacing and the line below.
        .padding(EdgeInsets(top: TrackColumns.rowPadding, leading: TrackColumns.inset,
                            bottom: TrackColumns.rowPadding, trailing: TrackColumns.inset))
        .trackRowDivider()
        .padding(.horizontal, 32)
    }
}
