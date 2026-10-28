import Foundation
import ITDBKit
import ClickwillModel

/// `audio [--fix ID[,ID] | --fix-all] (--keep-originals FOLDER | --discard-originals) [--apply]`
/// - checks whether the files on the iPod are in a format the device will play,
/// and if needed transcodes them to the highest supported one.
enum AudioCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let library = onDevice.library
        let paths = device.paths
        struct Finding { let track: ITTrack; let stream: AudioStream; let verdict: AudioCompatibility.Verdict }
        var findings: [Finding] = []
        var unreadable: [ITTrack] = []
        var supported = 0
        for track in library.tracks {
            guard let url = track.fileURL(on: paths), FileManager.default.fileExists(atPath: url.path) else { continue }
            guard let stream = await AudioFiles.stream(at: url) else { unreadable.append(track); continue }
            let verdict = AudioCompatibility.verdict(for: stream, purpose: .playing)
            if verdict.isSupported { supported += 1 } else { findings.append(Finding(track: track, stream: stream, verdict: verdict)) }
        }
        report("File formats", [
            ("the iPod plays", "\(supported)"),
            ("the iPod does not play", "\(findings.count)"),
            ("unreadable", "\(unreadable.count)"),
        ])
        for f in findings.sorted(by: { ($0.track.album ?? "") < ($1.track.album ?? "") }) {
            let target: String = { if case .convertible(_, let t) = f.verdict { return " -> \(t.label)" } else { return " (cannot be fixed)" } }()
            print("  id=\(f.track.uniqueID)  \(f.track.album ?? "?") / \(f.track.title ?? "?")")
            print("      \(AudioCompatibility.label(for: f.stream)): \(f.verdict.reason ?? "")\(target)")
        }
        guard findings.count > 0 else { return }

        var wanted: Set<UInt32> = []
        if call.has("--fix-all") { wanted = Set(findings.map { $0.track.uniqueID }) }
        else if let list = call.value(for: "--fix") { wanted = Set(list.split(separator: ",").compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }) }
        guard !wanted.isEmpty else {
            print("\n  To fix: --fix ID[,ID] or --fix-all (add --apply to write).")
            return
        }
        let chosen = findings.filter { wanted.contains($0.track.uniqueID) }
        guard !chosen.isEmpty else { throw CommandError("none of the given ids needs conversion") }
        print("\nTo transcode: \(chosen.count)")

        // The conversion loses information relative to the source (24 bits -> 16), so the original
        // must have somewhere to go. Without an explicit decision we do not touch the files.
        let archiveDirectory = call.value(for: "--keep-originals").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
        let discard = call.has("--discard-originals")
        if archiveDirectory == nil, !discard {
            print("")
            print("  Where should the originals go? A 24 -> 16 bit conversion cannot be undone.")
            print("    --keep-originals FOLDER    copies the files from before the conversion")
            print("    --discard-originals        deliberately without a copy")
            return
        }
        print(archiveDirectory.map { "  Originals: \($0.path)" } ?? "  Originals: NO COPY (--discard-originals)")
        guard call.has("--apply") else { print("  That was a preview. To write: add --apply"); return }

        // The same path as a conversion from the app window: the original to the archive,
        // the new file next to the old one, the database, the old file only after the database write;
        // on an error the new files disappear from the iPod.
        var changes = ChangeSet()
        for f in chosen {
            guard case .convertible(_, let target) = f.verdict, let source = f.track.fileURL(on: paths) else { continue }
            changes.queueConversion(trackID: f.track.uniqueID, album: f.track.album ?? "", title: f.track.title ?? "?",
                                    source: source, to: target, fromLabel: AudioCompatibility.label(for: f.stream),
                                    keepOriginalIn: archiveDirectory)
        }
        announce(try await onDevice.write(library, changes: changes, note: "ipodctl audio --fix (\(chosen.count))"))
    }
}
