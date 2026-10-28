import AVFoundation
import Observation
import ClickwillModel

/// The adapter does not move AVAudioPlayer between actors.
@MainActor
private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let finished: @MainActor @Sendable (Bool) -> Void
    private let failed: @MainActor @Sendable (String) -> Void

    init(finished: @escaping @MainActor @Sendable (Bool) -> Void,
         failed: @escaping @MainActor @Sendable (String) -> Void) {
        self.finished = finished
        self.failed = failed
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.finished(flag) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let message = error?.localizedDescription ?? "The audio file couldn't be decoded."
        Task { @MainActor [weak self] in self?.failed(message) }
    }
}

@MainActor
@Observable
final class PlaybackController {
    private(set) var currentTrack: TrackRow?
    private(set) var currentAlbum: AlbumCard?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?
    private var volumeLevel: Float = 0.62
    var volume: Float {
        get { volumeLevel }
        set {
            volumeLevel = newValue.isFinite ? min(max(newValue, 0), 1) : 0
            player?.volume = volumeLevel
        }
    }

    @ObservationIgnored private var queue = PlaybackQueue([])
    /// The track file - asked for each track, because the iPod may disappear in the meantime.
    @ObservationIgnored private let fileURL: @MainActor (TrackRow) -> URL?
    /// A website demo recording plays silently - the volume slider stays as it was.
    @ObservationIgnored private let muted: Bool
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var delegate: PlaybackDelegate?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var session = UUID()

    init(fileURL: @escaping @MainActor (TrackRow) -> URL?, muted: Bool = false) {
        self.fileURL = fileURL
        self.muted = muted
    }

    isolated deinit { timer?.invalidate() }

    func play(_ tracks: [TrackRow], startingAt: TrackRow?, in album: AlbumCard) {
        releasePlayer()
        currentAlbum = album
        errorMessage = nil
        queue = PlaybackQueue(tracks, startingAt: startingAt)
        guard let track = queue.currentTrack else {
            errorMessage = "None of these songs has an audio file on the iPod."
            return
        }
        open(track, direction: .forward)
    }

    /// Releases the audio file and everything tied to it.
    ///
    /// Needed before ejecting the iPod: `AVAudioPlayer` holds an open
    /// descriptor to a file that lies **on the volume being ejected**, so as long as
    /// it lives, the system refuses to eject with error -47. The app then blocked
    /// its own "eject" button and blamed Apple Music for it.
    func stop() {
        releasePlayer()
        isPlaying = false
        currentAlbum = nil
        queue = PlaybackQueue([])
    }

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            currentTime = player.currentTime
            stopTimer()
        } else {
            if currentTime >= duration { player.currentTime = 0 }
            guard player.play() else {
                errorMessage = "Couldn't resume playback."
                advanceAfterFailure()
                return
            }
            currentTime = player.currentTime
            startTimer()
        }
    }

    func next() {
        guard let track = queue.next() else {
            player?.stop()
            currentTime = duration
            stopTimer()
            return
        }
        open(track, direction: .forward)
    }

    func previous() {
        guard let track = queue.previous() else {
            seek(to: 0)
            return
        }
        open(track, direction: .backward)
    }

    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite, let player else { return }
        let target = min(max(seconds, 0), duration)
        player.currentTime = target
        currentTime = target
        if isPlaying, target >= duration { next() }
    }

    private enum Direction { case forward, backward }

    /// A loop instead of recursion: the whole library may have unavailable files.
    private func open(_ first: TrackRow, direction: Direction) {
        releasePlayer()
        var candidate: TrackRow? = first
        while let track = candidate {
            if let url = fileURL(track) {
                do {
                    let audio = try AVAudioPlayer(contentsOf: url)
                    audio.volume = muted ? 0 : volume
                    let token = session
                    let adapter = PlaybackDelegate { [weak self] success in
                        guard let self, self.session == token else { return }
                        if !success { self.errorMessage = "Playback failed for “\(track.displayTitle)”." }
                        self.next()
                    } failed: { [weak self] message in
                        guard let self, self.session == token else { return }
                        self.errorMessage = "Couldn't play “\(track.displayTitle)”: \(message)"
                        self.advanceAfterFailure()
                    }
                    audio.delegate = adapter
                    if audio.prepareToPlay(), audio.play() {
                        player = audio
                        delegate = adapter
                        currentTrack = track
                        duration = audio.duration
                        currentTime = audio.currentTime
                        startTimer()
                        return
                    }
                    audio.delegate = nil
                    errorMessage = "Couldn't start “\(track.displayTitle)”."
                } catch {
                    errorMessage = "Couldn't open “\(track.displayTitle)”: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "“\(track.displayTitle)” has no audio file here."
            }
            candidate = direction == .forward ? queue.next() : queue.previous()
        }
    }

    private func advanceAfterFailure() {
        if let track = queue.next() { open(track, direction: .forward) }
        else { releasePlayer() }
    }

    private func releasePlayer() {
        stopTimer()
        session = UUID()
        player?.delegate = nil
        player?.stop()
        player = nil
        delegate = nil
        currentTrack = nil
        currentTime = 0
        duration = 0
    }

    private func startTimer() {
        stopTimer()
        isPlaying = true
        let token = session
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying, self.session == token, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
}
