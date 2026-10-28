import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Previewing a single file **from disk**, for the import sheets.
///
/// Deliberately separate from `PlaybackController`: that one plays the library from the iPod through
/// a queue and `TrackRow`, while here it is about one question - "is it really this
/// file". No queue, no moving on, one file at a time.
@MainActor
@Observable
final class PreviewPlayer {
    /// The identifier of the row playing now. `nil` means silence.
    private(set) var playingID: UUID?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    isolated deinit { timer?.invalidate() }

    func isPlaying(_ id: UUID) -> Bool { playingID == id && isPlaying }
    func isLoaded(_ id: UUID) -> Bool { playingID == id }

    /// A click on a row: the same file toggles pause, another one starts over.
    func toggle(_ id: UUID, url: URL) {
        if playingID == id {
            guard let player else { return stop() }
            if player.isPlaying {
                player.pause()
                isPlaying = false
                stopTimer()
            } else if player.play() {
                isPlaying = true
                startTimer()
            }
            return
        }
        start(id, url: url)
    }

    func seek(_ id: UUID, to seconds: TimeInterval) {
        guard playingID == id, let player, seconds.isFinite else { return }
        player.currentTime = min(max(seconds, 0), player.duration)
        currentTime = player.currentTime
    }

    func stop() {
        player?.stop()
        player = nil
        stopTimer()
        playingID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func start(_ id: UUID, url: URL) {
        stop()
        // The file may lie on a mounted disc or on a volume that
        // disappeared between choosing and clicking - that is why the error goes to the screen,
        // not to the log.
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            errorMessage = "Can't read “\(url.lastPathComponent)”. The file or its volume is gone."
            return
        }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            guard audio.prepareToPlay(), audio.play() else {
                errorMessage = "Couldn't play “\(url.lastPathComponent)”."
                return
            }
            player = audio
            playingID = id
            isPlaying = true
            duration = audio.duration
            currentTime = 0
            errorMessage = nil
            startTimer()
        } catch {
            errorMessage = "Couldn't play “\(url.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    /// Polling instead of a delegate: `AVAudioPlayerDelegate` is `nonisolated`,
    /// so under strict concurrency it would need an adapter hopping to
    /// the main actor. The progress bar needs a timer anyway.
    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

/// The preview button in a row of the import sheet.
struct PreviewButton: View {
    let id: UUID
    let url: URL
    @Bindable var preview: PreviewPlayer

    var body: some View {
        Button {
            preview.toggle(id, url: url)
        } label: {
            Image(systemName: preview.isPlaying(id) ? "pause.fill" : "play.fill")
        }
        // A system circular button instead of our own circle (native UI).
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .tint(preview.isLoaded(id) ? .accentColor : nil)
        .help(preview.isPlaying(id) ? "Stop the preview" : "Listen to this file")
    }
}

/// The preview progress bar - it appears only under the playing row.
/// Clickable, because the middle says more about recognizing a track than the first seconds.
struct PreviewScrubber: View {
    let id: UUID
    @Bindable var preview: PreviewPlayer

    var body: some View {
        let total = max(preview.duration, 0.01)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.sep).frame(height: 3)
                Capsule().fill(Theme.accent)
                    .frame(width: geometry.size.width * min(preview.currentTime / total, 1), height: 3)
            }
            .frame(height: 3)
            .contentShape(Rectangle().size(width: geometry.size.width, height: 14))
            .onTapGesture { location in
                preview.seek(id, to: total * (location.x / max(geometry.size.width, 1)))
            }
        }
        .frame(height: 14)
    }
}
