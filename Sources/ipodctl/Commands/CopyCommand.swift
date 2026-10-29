import Foundation
import ITDBKit
import ClickwillModel

/// `copy --from IPOD --album A [--album B ...] [--artist X] [--apply]` - albums
/// from another iPod; skips tracks the target already has. Descriptions come from the source database - files
/// from a CD import (AIFF) carry no tags at all, so we take only
/// the audio from the file.
enum CopyCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        guard let from = call.value(for: "--from") else { throw CommandError("copy needs --from (classic, nano, GUID or path)") }
        let source = try resolveDevice(from)
        guard source.identity != device.identity else { throw CommandError("the source and the target are the same iPod") }
        let sourceLibrary = try source.readLibrary()
        let albums = call.values(for: "--album")
        guard !albums.isEmpty else { throw CommandError("give at least one --album") }
        let artist = call.value(for: "--artist")

        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let capabilities = IPodCapabilities.resolve(for: device)
        var index = SongIndex(tracks: library.tracks)
        var additions: [PendingAddition] = []
        var sourceBytes: Int64 = 0
        print("From \(source.volume.name) (\(source.model.name)) to \(device.volume.name) (\(device.model.name))")
        for album in albums {
            let tracks = sourceLibrary.tracks
                .filter { $0.album == album && (artist == nil || $0.effectiveAlbumArtist == artist || $0.artist == artist) }
                .sorted { ($0.discNumber, $0.trackNumber) < ($1.discNumber, $1.trackNumber) }
            guard !tracks.isEmpty else { throw CommandError("\(source.volume.name) has no album '\(album)'") }
            print("\n\(album) - \(tracks.count) tracks")
            for track in tracks {
                guard let url = track.fileURL(on: source.paths), FileManager.default.fileExists(atPath: url.path) else {
                    print("  SKIPPED: \(track.title ?? "?") - no file on the source"); continue
                }
                let candidate = try await AudioImport.candidate(at: url, on: capabilities)
                var draft = candidate.draft
                draft.title = track.title ?? draft.title
                draft.artist = track.artist
                draft.albumArtist = track.albumArtist
                draft.album = track.album
                draft.genre = track.genre
                draft.composer = track.composer
                draft.year = track.year
                draft.trackNumber = track.trackNumber
                draft.totalTracks = track.totalTracks
                draft.discNumber = track.discNumber
                draft.totalDiscs = track.totalDiscs
                draft.isCompilation = track.isCompilation
                // When the file did not reveal its bitrate (it happens with MP3), we take
                // it from the source database - iTunes measured it.
                if draft.bitRate == 0, candidate.verdict.isSupported { draft.bitRate = track.bitRate }
                if let place = index.place(of: draft) {
                    print("  ALREADY THERE: \(draft.title) (\(place))"); continue
                }
                index = SongIndex(tracks: library.tracks, queued: additions.map(\.draft) + [draft])
                let mark = candidate.verdict.isSupported ? " " : "!"
                print("  \(mark) \(String(format: "%02u", draft.trackNumber)) \(draft.title)  \(candidate.formatLabel)  \(formatted(bytes: Int64(draft.sizeBytes)))")
                if case .convertible(let reason, let target) = candidate.verdict {
                    print("      -> \(target.label): \(reason)")
                }
                sourceBytes += Int64(draft.sizeBytes)
                // Artwork only after testing the nano's formats on screen.
                additions.append(PendingAddition(id: UUID(), draft: draft, source: url, verdict: candidate.verdict,
                                                 formatLabel: candidate.formatLabel, cover: nil))
            }
        }
        guard !additions.isEmpty else { throw CommandError("there is nothing to copy") }
        // An upper estimate: conversion can only make files smaller.
        let free = device.volume.availableCapacity
        let margin: Int64 = 50_000_000
        print("\nTo copy: \(additions.count) tracks, at most \(formatted(bytes: sourceBytes)); free on the target: \(formatted(bytes: free))")
        guard sourceBytes + margin < free else {
            throw CommandError("not enough space: up to \(formatted(bytes: sourceBytes)) + \(formatted(bytes: margin)) reserve is needed")
        }
        try await previewAndApply(additions, to: onDevice, note: "ipodctl copy from \(source.volume.name)")
    }
}
