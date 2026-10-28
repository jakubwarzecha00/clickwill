import Foundation
import ITDBKit
import ClickwillModel

/// `add FILE|FOLDER ... [--title T] [--artist A] [--album B] [--track N] [--apply]`
/// - adding tracks to the library; without `--apply` only a preview.
enum AddCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let sources = call.positional(valueFlags: ["--title", "--artist", "--album", "--track"])
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        guard !sources.isEmpty else { throw CommandError("give files or folders to add") }

        var (candidates, problems) = await AudioImport.candidates(at: sources)
        for problem in problems { print("  SKIPPED: \(problem)") }
        guard !candidates.isEmpty else { throw CommandError("no audio files found") }

        // Field overrides - for files without tags.
        // --artist and --album describe the whole album, so they work for a batch too.
        // --title and --track describe one track - with a batch they would give all of them
        // the same value, so they are allowed only for a single file.
        if let a = call.value(for: "--artist") {
            for index in candidates.indices { candidates[index].draft.artist = a; candidates[index].draft.albumArtist = a }
        }
        if let b = call.value(for: "--album") {
            for index in candidates.indices { candidates[index].draft.album = b }
        }
        let single = ["--title", "--track"].filter { call.value(for: $0) != nil }
        if !single.isEmpty {
            guard candidates.count == 1 else { throw CommandError("\(single.joined(separator: ", ")) works only with a single file") }
            if let t = call.value(for: "--title") { candidates[0].draft.title = t }
            if let n = call.value(for: "--track").flatMap({ UInt32($0) }) { candidates[0].draft.trackNumber = n }
        }

        let onDevice = try DeviceLibrary(reading: device, for: call)
        print("Files found: \(candidates.count)")
        var playable: [AudioImport.Candidate] = []
        var needConversion: [AudioImport.Candidate] = []
        for candidate in candidates {
            let mark = candidate.verdict.isSupported ? " " : "!"
            print("  \(mark) \(candidate.draft.trackNumber > 0 ? String(format: "%02u ", candidate.draft.trackNumber) : "   ")\(candidate.draft.title)")
            print("      \(candidate.draft.artist ?? "?") / \(candidate.draft.album ?? "?")  \(candidate.formatLabel)  \(formatted(bytes: Int64(candidate.draft.sizeBytes)))")
            if let reason = candidate.verdict.reason { print("      the iPod will not play this: \(reason)") }
            if candidate.verdict.isSupported { playable.append(candidate) } else { needConversion.append(candidate) }
        }
        if !needConversion.isEmpty {
            // When adding, the original stays on the Mac, so there is nothing to ask about -
            // we convert the copy that goes to the iPod.
            print("\nTo transcode before adding: \(needConversion.count) (the originals stay where they are)")
        }

        try await previewAndApply((playable + needConversion).map(PendingAddition.init), to: onDevice, note: "ipodctl add")
    }
}
