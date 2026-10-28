import SwiftUI
import ClickwillModel

/// Reordering in the iPod-compatible version: the list cut into Cover Flow groups.
/// An album is dragged within its group (the album table); an album with the compilation
/// flag can be taken out of it. The order of the artists themselves cannot be
/// changed: the iPod places them in Cover Flow itself, by name. The preview on the right is the strip as
/// the iPod will show it.
struct ReorderScreen: View {
    @Environment(LibraryModel.self) private var model
    @State private var error: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("The order the iPod shows. Drag albums within an artist. The iPod puts artists in alphabetical order itself, and compilations sit at the end.")
                        .font(.theme(.body)).foregroundStyle(Theme.f2)
                    Spacer()
                }
                .padding(EdgeInsets(top: 14, leading: 24, bottom: 12, trailing: 24))
                List {
                    ForEach(model.coverFlowGroups) { group in
                        Section {
                            ForEach(Array(group.albums.enumerated()), id: \.element.id) { index, album in
                                ReorderRow(index: index, album: album)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 6, trailing: 24))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .contextMenu {
                                        if album.isCompilation {
                                            Button("Take Out of Compilations") { model.setCompilation(album, false) }
                                        } else {
                                            Button("Mark as Compilation") { model.setCompilation(album, true) }
                                        }
                                    }
                            }
                            .onMove { offsets, destination in
                                guard let from = offsets.first else { return }
                                attempt { try model.moveAlbumWithinGroup(group.albums[from], in: group, toOffset: destination) }
                            }
                        } header: {
                            GroupHeader(group: group)
                            .listRowInsets(EdgeInsets(top: 10, leading: 24, bottom: 6, trailing: 24))
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity)
            Divider().overlay(Theme.sep)
            preview
        }
        .background(Theme.stage)
        .alert("The albums couldn't be moved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { self.error = ErrorPresenter.message(for: error) }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On the iPod").font(.theme(.row, weight: .semibold))
            Text("On the iPod, left to right").font(.theme(.footnote)).foregroundStyle(Theme.f2).padding(.top, -6)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.coverFlowGroups) { group in
                        Text(group.title.uppercased())
                            .font(.theme(.fine, weight: .semibold)).foregroundStyle(Theme.f3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 8, leading: 12, bottom: 3, trailing: 12))
                        ForEach(group.albums) { album in
                            HStack(spacing: 10) {
                                Text(album.displayTitle).font(.theme(.body)).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right").font(.symbol(.small, weight: .bold)).foregroundStyle(Theme.f3)
                            }
                            .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                            .overlay(alignment: .bottom) { Theme.sep.frame(height: 0.5) }
                        }
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.sep, lineWidth: 0.5))
            }
        }
        .padding(18)
        .frame(width: 280)
    }
}

struct GroupHeader: View {
    let group: CoverFlowGroup

    var body: some View {
        HStack(spacing: 8) {
            Text(group.title).font(.theme(.callout, weight: .semibold)).foregroundStyle(Theme.f2)
            Text("\(group.albums.count)").font(.theme(.caption)).foregroundStyle(Theme.f3).monospacedDigit()
            if group.kind == .compilations {
                Text("albums flagged as compilations. Right-click to take one out")
                    .font(.theme(.caption)).foregroundStyle(Theme.warn)
            }
            Spacer()
        }
        .textCase(nil)
    }
}

struct ReorderRow: View {
    @Environment(LibraryModel.self) private var model
    let index: Int
    let album: AlbumCard
    private var image: CGImage? { model.artwork(for: album.artworkTrackID) }

    var body: some View {
        HStack(spacing: 14) {
            Text("\(index + 1)").frame(width: 20, alignment: .trailing).font(.theme(.row)).foregroundStyle(Theme.f2).monospacedDigit()
            Group {
                if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) }
                else { ZStack { Theme.card; Image(systemName: "music.note").foregroundStyle(Theme.f3) } }
            }
            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(album.displayTitle).font(.theme(.rowLarge, weight: .medium)).lineLimit(1)
                Text(album.displayArtist).font(.theme(.callout)).foregroundStyle(Theme.f2).lineLimit(1)
            }
            Spacer()
            if album.isCompilation {
                Text("compilation").font(.theme(.small)).foregroundStyle(Theme.warn)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.warn.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
            }
            Image(systemName: "line.3.horizontal").foregroundStyle(Theme.f3)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(Theme.row, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.sep, lineWidth: 0.5))
        .task(id: album.artworkTrackID) { await model.ensureArtwork(for: album.artworkTrackID) }
    }
}
