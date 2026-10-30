import SwiftUI
import ClickwillModel
import ITDBKit

/// Diagnostics for screenshots (`--screen diagnostics`, `--screen rockbox`): a demo library is a
/// backup on disk, not a device, so there is nothing to measure. The example is the iPod Video
/// from issue #1 with Rockbox next to Apple's firmware.
struct SampleDiagnostics: Sendable {
    let diagnostics: Diagnostics
    let rockbox: RockboxInstallation
    let rockboxReport: RockboxReport

    static let video = SampleDiagnostics(
        diagnostics: Diagnostics(checks: [
            .init(id: .usb, weight: .required, status: .passed, detail: "0x1209 · iPod (5th generation) · unsigned family"),
            .init(id: .firmwareDescription, weight: .advisory, status: .warning,
                  detail: "no SysInfoExtended from firmware (common with modified firmware)"),
            .init(id: .identity, weight: .required, status: .passed, detail: "USB, firmware and database agree"),
            .init(id: .format, weight: .required, status: .passed, detail: "scheme 0 (unsigned) · header 244 B · version 0x19"),
            .init(id: .rebuild, weight: .required, status: .passed, detail: "rebuilt in memory: 4812336 B, byte-identical"),
            .init(id: .playCounts, weight: .advisory, status: .passed, detail: "no Play Counts file"),
            .init(id: .files, weight: .advisory, status: .warning,
                  detail: "2418 entries, 2415 files · 3 entries without a file · 0 files without an entry · 0 size mismatches · 0 dead playlist references"),
            .init(id: .artwork, weight: .advisory, status: .warning,
                  detail: "212 images · formats 1028, 1029 · 1028, 1029 not measured · new artwork disabled"),
            .init(id: .volume, weight: .required, status: .passed, detail: "writable · 12.4 GB free"),
            .init(id: .music, weight: .advisory, status: .passed, detail: "Music is not running"),
        ], confirmedModel: false, unsigned: true, measurements: [
            "firmware/load: Play Counts written 1 min after iTunesDB · 2418 entries for 2418 songs · the Apple firmware loaded this iTunesDB",
            "structure: 4812336 B · mhbd 244 ×1 · mhsd 96 ×4 (types 1,2,3,4) · mhlt 92 ×1 · mhit 584 ×2418 · mhod 24 ×21940 (types 1,2,3,4,5,6,52,53,100) · mhlp 92 ×2 · mhyp 108 ×6 · mhip 76 ×4911",
            "artwork/formats: 1028 not in SysInfoExtended (not measured), 1029 not in SysInfoExtended (not measured)",
            "rockbox/install: 4.0 · ipodvideo",
            "rockbox/settings: tagcache_autoupdate on · tagcache_ram off (default) · dircache on (default) · database scan paths / (default) · database path /.rockbox (default) · gather runtime data off (default)",
            "rockbox/database: version 0x10 · 2421 entries, 0 marked deleted · commit 9 · written 3 h 12 min after iTunesDB",
            "rockbox/coverage: 2418 songs in iTunesDB · 2415 in Rockbox database · 3 not in it · 0 Rockbox entries for files gone from iPod_Control · 6 Rockbox entries outside iPod_Control",
            "rockbox/activity: last run 3 h 40 min after iTunesDB",
            "rockbox/effect: iTunesDB edits not read by Rockbox (file tags only) · added and removed files reach its database at boot (tagcache_autoupdate on)",
        ]),
        rockbox: RockboxInstallation(version: "4.0", target: "ipodvideo"),
        rockboxReport: RockboxReport(installation: RockboxInstallation(version: "4.0", target: "ipodvideo"), albums: [
            .init(title: "OK Computer", artist: "Radiohead", issues: [.artworkOnlyInLibrary(tracks: 12)]),
            .init(title: "In Rainbows", artist: "Radiohead", issues: [.artworkNotShown(.png, tracks: 10)]),
            .init(title: "Now That's What I Call Music! 63", artist: "Various Artists", issues: [.untaggedCompilation(tracks: 21)]),
            .init(title: "Kid A", artist: "Radiohead", issues: [.tagsDiffer(fields: ["title"], tracks: 2)]),
        ], scannedTracks: 2418))
}

extension EnvironmentValues {
    /// Set only on a screenshot launch.
    @Entry var sampleDiagnostics: SampleDiagnostics? = nil
}
