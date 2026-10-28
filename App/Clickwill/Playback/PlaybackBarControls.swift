import SwiftUI
import ClickwillModel

struct PlaybackBarControls: View {
    @Environment(LibraryModel.self) private var model
    @Environment(PlaybackController.self) private var playback
    @State private var scrubbing = false
    @State private var scrubTime: Double = 0
    @State private var showError = false

    private var displayedTime: Double { scrubbing ? scrubTime : playback.currentTime }

    var body: some View {
        @Bindable var playback = playback
        HStack(spacing: 12) {
            HStack(spacing: 13) {
                Button(action: playback.previous) { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Previous track")
                    .help("Previous track")
                Button(action: playback.togglePlayPause) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.symbol(.large)).foregroundStyle(Theme.fg)
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                .help(playback.isPlaying ? "Pause (Space)" : "Play (Space)")
                Button(action: playback.next) { Image(systemName: "forward.end.fill") }
                    .accessibilityLabel("Next track")
                    .help("Next track")
            }
            .font(.symbol(.medium)).foregroundStyle(Theme.f2)
            .buttonStyle(.plain)
            .disabled(playback.currentTrack == nil)

            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(playback.currentTrack?.displayTitle ?? "Nothing playing")
                    .font(.theme(.body, weight: .semibold))
                Text(subtitle)
                    .font(.theme(.footnote)).foregroundStyle(Theme.f2)
            }
            .lineLimit(1)
            .frame(minWidth: 70, idealWidth: 165, maxWidth: 165, alignment: .leading)

            HStack(spacing: 9) {
                Text(displayedTime.clockLabel).fixedSize()
                Slider(value: Binding(
                    get: { min(displayedTime, playback.duration) },
                    set: {
                        scrubTime = $0
                        if !scrubbing { playback.seek(to: $0) }
                    }
                ), in: 0...max(playback.duration, 0.001)) { editing in
                    if editing {
                        scrubTime = playback.currentTime
                        scrubbing = true
                    } else {
                        playback.seek(to: scrubTime)
                        scrubbing = false
                    }
                }
                .controlSize(.mini)
                .disabled(playback.currentTrack == nil || playback.duration <= 0)
                .accessibilityLabel("Playback position")
                Text("-\(max(0, playback.duration - displayedTime).clockLabel)").fixedSize()
            }
            .font(.theme(.small)).foregroundStyle(Theme.f2).monospacedDigit()
            .frame(minWidth: 110, maxWidth: 300)

            HStack(spacing: 7) {
                Image(systemName: playback.volume == 0 ? "speaker.fill" : "speaker.wave.2.fill")
                    .font(.theme(.callout)).foregroundStyle(Theme.f2)
                Slider(value: $playback.volume, in: 0...1)
                    .controlSize(.mini).accessibilityLabel("Volume")
            }
            .frame(width: 88)

            if let message = playback.errorMessage {
                Button { showError.toggle() } label: {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.warn)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback error: \(message)")
                .help(message)
                .popover(isPresented: $showError) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Playback issue").font(.headline)
                        Text(message).font(.callout).textSelection(.enabled)
                        Button("Dismiss") { showError = false; playback.errorMessage = nil }
                    }.padding().frame(width: 320)
                }
            }
        }
        .tint(Theme.fg.opacity(0.75))
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: playback.currentAlbum?.artworkTrackID) {
            await model.ensureArtwork(for: playback.currentAlbum?.artworkTrackID)
        }
        .onChange(of: playback.currentTrack?.id) { scrubbing = false }
    }

    private var subtitle: String {
        guard let track = playback.currentTrack, let album = playback.currentAlbum else { return "Select a song to preview" }
        let artist = track.artist.isEmpty ? album.displayArtist : track.artist
        return "\(artist) · \(album.displayTitle)"
    }

    private var artwork: some View {
        ZStack {
            Theme.card
            if let image = model.artwork(for: playback.currentAlbum?.artworkTrackID) {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").foregroundStyle(Theme.f3)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.3), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}
