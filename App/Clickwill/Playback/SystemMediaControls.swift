import AppKit
import MediaPlayer
import ClickwillModel

/// The media keys on the Mac keyboard (F7, F8, F9) and the "Now
/// Playing" item in the system menu.
///
/// The system does not send these keys to just any app - they go to the one
/// that registered as playing through `MPNowPlayingInfoCenter`.
/// That is why hooking up the commands is not enough: one must also describe what is playing, and
/// keep that description in line with the player state.
@MainActor
final class SystemMediaControls {
    private let playback: PlaybackController
    /// Album artwork by the identifier of a track with artwork.
    private let artwork: @MainActor (UInt64) -> CGImage?
    private var artworkKey: UInt64?

    init(playback: PlaybackController, artwork: @escaping @MainActor (UInt64) -> CGImage?) {
        self.playback = playback
        self.artwork = artwork
        connectCommands()
        observe()
        publish()
    }

    private func connectCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.playback.currentTrack != nil else { return .noSuchContent }
            self.playback.togglePlayPause()
            return .success
        }
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self, self.playback.currentTrack != nil else { return .noSuchContent }
            if !self.playback.isPlaying { self.playback.togglePlayPause() }
            return .success
        }
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.playback.currentTrack != nil else { return .noSuchContent }
            if self.playback.isPlaying { self.playback.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.playback.currentTrack != nil else { return .noSuchContent }
            self.playback.next()
            return .success
        }
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.playback.currentTrack != nil else { return .noSuchContent }
            self.playback.previous()
            return .success
        }
        // Seeking from the system bar and from AirPods.
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent,
                  self.playback.currentTrack != nil else { return .noSuchContent }
            self.playback.seek(to: event.positionTime)
            return .success
        }
        // We do not handle these - enabled, they would take the keys and do nothing.
        for unsupported in [center.seekForwardCommand, center.seekBackwardCommand,
                            center.skipForwardCommand, center.skipBackwardCommand,
                            center.changeRepeatModeCommand, center.changeShuffleModeCommand] {
            unsupported.isEnabled = false
        }
    }

    /// We track only what changes the track description. `currentTime` changes every
    /// quarter second, and the system adds the elapsed time since the last report by itself anyway.
    private func observe() {
        withObservationTracking {
            _ = playback.currentTrack?.id
            _ = playback.isPlaying
            _ = playback.duration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.publish()
                self.observe()
            }
        }
    }

    /// MediaPlayer calls the artwork closure from its own queue, not from
    /// the main thread. Built in a `@MainActor` context, it would carry
    /// an isolation check that ends the process at that point - hence
    /// `nonisolated`, so that there is no check at all.
    private nonisolated static func artwork(from image: CGImage) -> MPMediaItemArtwork {
        let size = CGSize(width: image.width, height: image.height)
        let cover = NSImage(cgImage: image, size: size)
        return MPMediaItemArtwork(boundsSize: size) { _ in cover }
    }

    private func publish() {
        let center = MPNowPlayingInfoCenter.default()
        guard let track = playback.currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            artworkKey = nil
            return
        }
        let album = playback.currentAlbum
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.artist.isEmpty ? (album?.displayArtist ?? "") : track.artist,
            MPMediaItemPropertyPlaybackDuration: playback.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playback.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playback.isPlaying ? 1.0 : 0.0,
        ]
        if let title = album?.displayTitle { info[MPMediaItemPropertyAlbumTitle] = title }
        if let id = album?.artworkTrackID, let image = artwork(id) {
            info[MPMediaItemPropertyArtwork] = Self.artwork(from: image)
            artworkKey = id
        }
        center.nowPlayingInfo = info
        center.playbackState = playback.isPlaying ? .playing : .paused
    }
}
