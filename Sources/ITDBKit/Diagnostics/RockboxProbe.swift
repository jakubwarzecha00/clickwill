import Foundation

/// Everything on the disk that says how a write by Clickwill reaches Rockbox: its database
/// settings, its own database and when it last ran. Read-only.
///
/// Rules from Rockbox's source (`apps/settings_list.c`, `apps/tagcache.c`):
/// `config.cfg` keeps only settings changed from the default, so a missing key is the default;
/// the database scan goes through every folder except `.` and `..`, `iPod_Control/Music`
/// included, and skips a folder with `database.ignore`.
public struct RockboxProbe: Sendable {

    public enum DatabaseState: Sendable, Equatable {
        /// No `database_idx.tcd`: Database › Initialize Now was never run.
        case absent
        case readable(RockboxDatabase)
        case unreadable(String)
    }

    public struct Setting: Sendable, Equatable {
        public let key: String
        public let value: String
        /// Not in `config.cfg` - Rockbox uses its default.
        public let isDefault: Bool
    }

    public let installation: RockboxInstallation
    /// The settings that decide what the database sees and when it updates.
    public let settings: [Setting]
    public let database: DatabaseState
    /// `database_tmp.tcd`: a scan finished but not committed yet (Rockbox commits at the next boot).
    public let scanPending: Bool
    public let databaseModified: Date?
    /// The newest of the files Rockbox writes while it runs.
    public let lastActivity: Date?

    public init(installation: RockboxInstallation, settings: [Setting], database: DatabaseState,
                scanPending: Bool, databaseModified: Date?, lastActivity: Date?) {
        self.installation = installation
        self.settings = settings
        self.database = database
        self.scanPending = scanPending
        self.databaseModified = databaseModified
        self.lastActivity = lastActivity
    }

    /// Rockbox 4.0 defaults of the settings we report.
    static let defaults: [(key: String, value: String)] = [
        ("tagcache_autoupdate", "off"), ("tagcache_ram", "off"), ("dircache", "on"),
        ("database scan paths", "/"), ("database path", "/.rockbox"), ("gather runtime data", "off"),
    ]

    /// Files Rockbox rewrites while it runs or shuts down (`nvram.bin` in older releases).
    static let activityFiles = ["config.cfg", ".resume.cfg", ".playlist_control", "nvram.bin"]

    public var autoUpdate: Bool { settings.first { $0.key == "tagcache_autoupdate" }?.value == "on" }

    /// `nil` when the volume has no `.rockbox` folder.
    public static func read(at mountPoint: URL) -> RockboxProbe? {
        guard let installation = RockboxInstallation.detect(at: mountPoint) else { return nil }
        let folder = mountPoint.appendingPathComponent(".rockbox", isDirectory: true)
        let config = (try? String(contentsOf: folder.appendingPathComponent("config.cfg"), encoding: .utf8)) ?? ""
        let settings = parseSettings(config)

        // "database path" is a path on the iPod; a crafted one must not lead outside it.
        let stated = settings.first { $0.key == "database path" }?.value ?? "/.rockbox"
        let relative = stated.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let databaseFolder = relative.isEmpty ? mountPoint : ContainedPath.resolve(relative, in: mountPoint)

        let database: DatabaseState
        if let databaseFolder {
            do {
                database = try RockboxDatabase.read(folder: databaseFolder).map(DatabaseState.readable) ?? .absent
            } catch {
                database = .unreadable("\(error)")
            }
        } else {
            database = .unreadable("database path \(stated) outside the iPod")
        }
        func modified(_ url: URL) -> Date? {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return RockboxProbe(
            installation: installation, settings: settings, database: database,
            scanPending: databaseFolder.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("database_tmp.tcd").path) } ?? false,
            databaseModified: databaseFolder.flatMap { modified($0.appendingPathComponent("database_idx.tcd")) },
            lastActivity: activityFiles.compactMap { modified(folder.appendingPathComponent($0)) }.max())
    }

    /// The reported settings: the known ones with their defaults filled in, and any other
    /// database setting an older or newer release writes under another name.
    static func parseSettings(_ config: String) -> [Setting] {
        var found: [String: String] = [:]
        var order: [String] = []
        for line in config.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if found[key] == nil { order.append(key) }
            found[key] = value
        }
        var settings = defaults.map { key, value in
            Setting(key: key, value: found[key] ?? value, isDefault: found[key] == nil)
        }
        let known = Set(defaults.map(\.key))
        for key in order where !known.contains(key) && ["tagcache", "database", "dircache"].contains(where: key.contains) {
            settings.append(Setting(key: key, value: found[key] ?? "", isDefault: false))
        }
        return settings
    }

    /// The songs of iTunesDB against Rockbox's database.
    public struct Coverage: Sendable, Equatable {
        /// Songs in iTunesDB with a file in `iPod_Control/Music`.
        public let songs: Int
        /// Of those, songs Rockbox has an entry for.
        public let inRockbox: Int
        /// Rockbox entries in `iPod_Control/Music` whose file is gone.
        public let staleEntries: Int
        /// Rockbox entries outside `iPod_Control/Music` - files the Apple firmware doesn't list.
        public let otherEntries: Int

        public var notInRockbox: Int { songs - inRockbox }
    }

    /// `nil` without a readable database. Paths compare without case, as on the iPod's FAT volume.
    public func coverage(of library: ITLibrary, paths: IPodPaths) -> Coverage? {
        guard case .readable(let database) = database else { return nil }
        let songs = Set(library.tracks.compactMap { $0.relativePath?.lowercased() })
        var known = Set<String>()
        var stale = 0, other = 0
        for path in database.paths {
            let relative = String(path.drop { $0 == "/" })
            let parts = relative.split(separator: "/")
            guard parts.count >= 3, parts[0].lowercased() == "ipod_control", parts[1].lowercased() == "music" else {
                other += 1
                continue
            }
            known.insert(relative.lowercased())
            let exists = paths.musicFile(relative).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            if !exists { stale += 1 }
        }
        return Coverage(songs: songs.count, inRockbox: songs.intersection(known).count, staleEntries: stale, otherEntries: other)
    }

    /// Technical lines for the diagnostic report. Times are given relative to iTunesDB,
    /// the file Clickwill writes, so no clock time leaves the Mac.
    public func reportLines(library: ITLibrary?, paths: IPodPaths, iTunesDBModified: Date?) -> [String] {
        var lines = ["rockbox/install: \(installation.version ?? "unknown version") · \(installation.target ?? "unknown target")"]
        lines.append("rockbox/settings: " + settings.map { "\($0.key) \(Self.reported($0))\($0.isDefault ? " (default)" : "")" }.joined(separator: " · "))
        switch database {
        case .absent:
            lines.append("rockbox/database: not built (Database › Initialize Now never run)")
        case .unreadable(let reason):
            lines.append("rockbox/database: unreadable - \(reason)")
        case .readable(let db):
            lines.append("rockbox/database: version 0x\(String(db.version, radix: 16)) · \(db.entries) entries, \(db.deleted) marked deleted"
                + " · commit \(db.commitID)\(db.dirty ? " · dirty" : "")\(scanPending ? " · scan not committed yet" : "")"
                + " · written \(Self.relative(databaseModified, to: iTunesDBModified))")
        }
        if let library, let coverage = coverage(of: library, paths: paths) {
            lines.append("rockbox/coverage: \(coverage.songs) songs in iTunesDB · \(coverage.inRockbox) in Rockbox database"
                + " · \(coverage.notInRockbox) not in it · \(coverage.staleEntries) Rockbox entries for files gone from iPod_Control"
                + " · \(coverage.otherEntries) Rockbox entries outside iPod_Control")
        }
        lines.append("rockbox/activity: last run \(Self.relative(lastActivity, to: iTunesDBModified))")
        let update = autoUpdate ? "at boot (tagcache_autoupdate on)" : "only after Database › Update Now (tagcache_autoupdate off)"
        lines.append("rockbox/effect: iTunesDB edits not read by Rockbox (file tags only) · added and removed files reach its database \(update)")
        return lines
    }

    /// Folder names the owner chose stay on the Mac: scan paths are reduced to whether
    /// they cover `iPod_Control`, a moved database to "elsewhere".
    static func reported(_ setting: Setting) -> String {
        switch setting.key {
        case "database scan paths":
            let paths = setting.value.split(separator: ":").map { $0.lowercased() }
            let covers = paths.contains { $0 == "/" || "/ipod_control/music".hasPrefix($0.hasSuffix("/") ? String($0.dropLast()) : $0) }
            return setting.value == "/" ? "/" : "\(paths.count) paths, iPod_Control \(covers ? "covered" : "not covered")"
        case "database path":
            return setting.value == "/.rockbox" ? setting.value : "elsewhere on the iPod"
        default:
            return setting.value
        }
    }

    /// "+2 h 5 min after iTunesDB", "40 s before iTunesDB", "unknown".
    static func relative(_ date: Date?, to reference: Date?) -> String {
        guard let date else { return "unknown" }
        guard let reference else { return "at an unknown time (no iTunesDB date)" }
        let seconds = Int(date.timeIntervalSince(reference).rounded())
        let magnitude = abs(seconds)
        let text = magnitude < 60 ? "\(magnitude) s"
            : magnitude < 3600 ? "\(magnitude / 60) min"
            : magnitude < 86_400 ? "\(magnitude / 3600) h \(magnitude % 3600 / 60) min"
            : "\(magnitude / 86_400) d"
        return seconds >= 0 ? "\(text) after iTunesDB" : "\(text) before iTunesDB"
    }
}
