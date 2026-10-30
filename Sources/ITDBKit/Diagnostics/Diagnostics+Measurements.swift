import Foundation

/// The raw measurements under the checks: what is needed to find the cause on a model we
/// have never held, from the report alone. Every line is technical; none carries a GUID,
/// a serial number, a title or a clock time.
extension Diagnostics {

    static func measurements(_ device: IPodDevice, _ database: Data?, _ library: ITLibrary?, checks: [Check]) -> [String] {
        var lines: [String] = []
        func failed(_ id: Check.ID) -> Bool { checks.first { $0.id == id }.map { $0.status != .passed } ?? false }

        if let description = device.firmwareDescription {
            lines.append("sysinfo: FamilyID \(description.familyID.map(String.init) ?? "?")"
                + " · UpdaterFamilyID \(description.updaterFamilyID.map(String.init) ?? "?")"
                + " · firmware \(description.firmwareVersion ?? "?") · model \(description.modelNumber ?? "?")"
                + " · artwork " + (description.albumArt.isEmpty ? "none"
                    : description.albumArt.map { "\($0.formatID) \($0.width)×\($0.height) \($0.pixelFormat)" }.joined(separator: ", ")))
        }

        let modified = Self.modificationDate(device.paths.iTunesDB)
        lines.append("firmware/load: " + firmwareLoad(device, library, iTunesDBModified: modified))

        if let database {
            let map = RecordMap.build(database)
            lines.append("structure: \(database.count) B · \(map.skeleton)")
            if failed(.format) {
                // Both identifiers zeroed: they name the database, not the format.
                var header = database.prefix(min(database.count, device.format.headerLength))
                for range in [0x18..<0x20, 0x24..<0x2C] where range.upperBound <= header.count {
                    header.replaceSubrange(range, with: Data(count: range.count))
                }
                lines.append("format/header: \(header.spacedHex(0..<header.count)) (identifiers at 0x18 and 0x24 zeroed)")
            }
            if failed(.rebuild) { lines += rebuildDetail(database, device: device, map: map) }
        }

        if failed(.playCounts), let data = try? Data(contentsOf: device.paths.playCounts) {
            let header = data.count >= 8 ? Int(data[data.startIndex + 4]) | Int(data[data.startIndex + 5]) << 8 : 0
            let entry = data.count >= 12 ? Int(data[data.startIndex + 8]) | Int(data[data.startIndex + 9]) << 8 : 0
            lines.append("playCounts/header: \(data.spacedHex(0..<min(header, 0x20, data.count)))")
            if entry > 0 {
                for index in 0..<3 where header + (index + 1) * entry <= data.count {
                    lines.append("playCounts/entry \(index): \(data.spacedHex((header + index * entry)..<(header + (index + 1) * entry)))")
                }
            }
        }

        if failed(.artwork), let artwork = try? device.readArtwork() {
            let stated = Dictionary(device.firmwareDescription?.albumArt.map { ($0.formatID, $0) } ?? [], uniquingKeysWith: { a, _ in a })
            let formats = artwork.formats.map { format in
                let image = stated[format.correlationID].map { " \($0.width)×\($0.height) \($0.pixelFormat)" } ?? " not in SysInfoExtended"
                return "\(format.correlationID)\(image)\(ConfirmedModels.artworkFormats.contains(format.correlationID) ? "" : " (not measured)")"
            }
            lines.append("artwork/formats: \(formats.joined(separator: ", "))")
        }

        if let rockbox = RockboxProbe.read(at: device.paths.mountPoint) {
            lines += rockbox.reportLines(library: library, paths: device.paths, iTunesDBModified: modified)
        }
        return lines
    }

    /// Evidence that the Apple firmware loaded the iTunesDB on the disk. The firmware writes
    /// Play Counts, one entry per song, against the database it has loaded; Clickwill and Music
    /// delete the file when they write. So a Play Counts newer than iTunesDB and as long as its
    /// song list means the firmware read this database. Its absence proves nothing: on the
    /// nano 2G the file came a minute after one write and not at all after the
    /// next, which the iPod did show.
    static func firmwareLoad(_ device: IPodDevice, _ library: ITLibrary?, iTunesDBModified: Date?) -> String {
        guard let written = modificationDate(device.paths.playCounts) else {
            return "no Play Counts · no evidence either way (the firmware doesn't write it after every load)"
        }
        let when = RockboxProbe.relative(written, to: iTunesDBModified)
        guard let counts = try? device.readPlayCounts() else { return "Play Counts written \(when) · unreadable" }
        let songs = library.map { "\($0.tracks.count) songs" } ?? "songs unknown"
        let loaded = (iTunesDBModified.map { written >= $0 } ?? false) && counts.entries.count == library?.tracks.count
        return "Play Counts written \(when) · \(counts.entries.count) entries for \(songs)"
            + (loaded ? " · the Apple firmware loaded this iTunesDB" : " · written for another iTunesDB")
    }

    /// The first differing places, each named by record and field; the shapes of both
    /// databases when the sizes differ.
    static func rebuildDetail(_ database: Data, device: IPodDevice, map: RecordMap) -> [String] {
        guard let trip = try? RoundTrip.measure(database, fireWireID: device.fireWireID?.bytes), !trip.isIdentical else { return [] }
        var lines: [String] = []
        // Length fields that only follow a record that grew or shrank - the effect, not the cause.
        var followingLengths = Set<Int>()
        // After a record changes size every later byte shifts; only the headers of the
        // records that changed say something then.
        var causeHeaders: [Range<Int>]?
        if trip.original.count != trip.rebuilt.count {
            let rebuilt = RecordMap.build(trip.rebuilt)
            lines.append("rebuild/rebuilt structure: \(trip.rebuilt.count) B · \(rebuilt.skeleton)")
            let changes = map.lengthChanges(comparedWith: rebuilt)
            followingLengths = Set(changes.ancestors.map { $0.offset + 8 })
            causeHeaders = changes.causes.map { $0.record.offset..<($0.record.offset + $0.record.headerLength) }
            for change in changes.causes.prefix(4) {
                let children = change.children.map { " · children \($0)" } ?? ""
                lines.append("rebuild/record: \(map.path(of: change.record)) · \(change.record.end - change.record.offset) B original,"
                    + " \(change.rebuiltLength) B rebuilt\(children)")
            }
        }
        let all = trip.differingRegions()
        let regions = all.filter { region in
            guard !followingLengths.contains(region.lowerBound) || region.count > 4 else { return false }
            return causeHeaders.map { $0.contains { $0.contains(region.lowerBound) } } ?? true
        }
        for region in regions.prefix(8) {
            let start = String(format: "0x%X", region.lowerBound)
            guard let location = map.locate(region.lowerBound) else {
                lines.append("rebuild/diff \(start) +\(region.count) B · outside any record")
                continue
            }
            let place = "\(location.path) +\(String(format: "0x%X", location.offsetInRecord)) (\(location.inHeader ? "header" : "body"))"
            let shown = region.lowerBound..<min(region.upperBound, region.lowerBound + 16)
            let bytes = location.isText ? "text, not shown"
                : "\(trip.original.spacedHex(shown)) → \(trip.rebuilt.spacedHex(shown))"
            lines.append("rebuild/diff \(start) +\(region.count) B · \(place) · \(bytes)")
        }
        if regions.count > 8 { lines.append("rebuild/diff: \(regions.count - 8) more regions") }
        if causeHeaders != nil, all.count > regions.count {
            lines.append("rebuild/diff: \(all.count - regions.count) regions after the change in size not listed (shifted bytes)")
        }
        return lines
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
