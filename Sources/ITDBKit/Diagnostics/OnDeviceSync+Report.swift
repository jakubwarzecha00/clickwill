import Foundation

/// The diagnostic report's lines about the on-device sync: what is installed, which entries it
/// owns and when it last ran. No folder names, file names or titles; times relative to iTunesDB.
extension OnDeviceSync {

    public func reportLines(library: ITLibrary?, paths: IPodPaths, iTunesDBModified: Date?) -> [String] {
        let install = [
            "FLAC/\(Self.stateFile) " + (stateVersion.map { "version \($0)" } ?? "missing"),
            "FLAC/\(Self.coverFile) \(hasCoverCache ? "present" : "missing")",
            "FLAC/\(Self.logFile) \(hasLog ? "present" : "missing")",
            "firmware images at the root: " + (firmwareImages.isEmpty ? "none" : firmwareImages.joined(separator: ", ")),
        ]
        var lines = ["devicesync/install: " + install.joined(separator: " · ")]

        if let library {
            let owned = library.tracks.filter(Self.manages)
            let flac = owned.filter { $0.rawHeader[MhitLayout.fileTypeCode] == Self.flacType }.count
            let found = owned.filter { Self.file(of: $0, on: paths).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }.count
            let markers = Dictionary(grouping: owned, by: Self.marker(of:)).mapValues(\.count)
            let markerText = markers.sorted { Self.order($0.key) < Self.order($1.key) }
                .map { "\(Self.label($0.key)) ×\($0.value)" }.joined(separator: ", ")
            lines.append("devicesync/tracks: \(owned.count) of \(library.tracks.count) songs owned"
                + " (\(flac) FLAC, \(owned.count - flac) videos outside iPod_Control)"
                + " · files \(found) found, \(owned.count - found) missing"
                + (markerText.isEmpty ? "" : " · markers \(markerText)"))
        }
        lines.append("devicesync/activity: last sync \(RockboxProbe.relative(stateModified, to: iTunesDBModified))"
            + " · log written \(RockboxProbe.relative(logModified, to: iTunesDBModified))")
        lines.append("devicesync/effect: rebuilds iTunesDB at boot and after every USB session · other entries kept as written"
            + " · owned entries follow their files: removal and cover changes refused, edits last until the file changes")
        return lines
    }

    static func label(_ marker: Marker) -> String {
        switch marker {
        case .version(let version): "FLSY v\(version)"
        case .blank: "blank"
        case .other: "other bytes"
        case .none: "short header"
        }
    }

    static func order(_ marker: Marker) -> Int {
        switch marker {
        case .version(let version): version
        case .blank: 1_000_000
        case .other: 1_000_001
        case .none: 1_000_002
        }
    }
}
