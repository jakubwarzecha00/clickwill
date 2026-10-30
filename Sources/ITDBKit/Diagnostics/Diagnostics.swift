import Foundation

/// What we can tell about a connected iPod without writing anything - for every model,
/// confirmed or not. Required checks decide whether an unconfirmed model may be allowed
/// experimental writing; advisory ones only warn.
///
/// Details are technical and carry no GUID, serial number, iPod name or track titles:
/// they go into the report the user copies (`DiagnosticReport`).
public struct Diagnostics: Sendable {

    public enum Group: String, Sendable, CaseIterable {
        case device, library, files, artwork, disk
    }

    public enum Status: String, Sendable {
        case passed, warning, failed, info
    }

    public enum Weight: Sendable {
        /// Must pass before experimental writing can be allowed.
        case required
        /// Reported; may block a write later, but not the permission.
        case advisory
    }

    public struct Check: Sendable, Identifiable {
        public enum ID: String, Sendable, CaseIterable {
            case usb, firmwareDescription, identity, format, rebuild, playCounts, files, artwork, volume, music
        }
        public let id: ID
        public let weight: Weight
        public let status: Status
        public let detail: String

        public init(id: ID, weight: Weight, status: Status, detail: String) {
            self.id = id
            self.weight = weight
            self.status = status
            self.detail = detail
        }

        public var group: Group {
            switch id {
            case .usb, .firmwareDescription, .identity: .device
            case .format, .rebuild, .playCounts: .library
            case .files: .files
            case .artwork: .artwork
            case .volume, .music: .disk
            }
        }
    }

    public let checks: [Check]
    /// Whether the device writes today under the standard policy - a confirmed model.
    public let confirmedModel: Bool
    /// Whether the database is unsigned - the only kind experimental writing covers.
    public let unsigned: Bool
    /// The raw data under the checks, for the report (`Diagnostics+Measurements`).
    public let measurements: [String]
    /// The policy the device had when checked - the verdict differs once a permission is given.
    public let policy: WritePolicy

    /// For screenshots and tests; `run(on:)` builds the real result.
    public init(checks: [Check], confirmedModel: Bool, unsigned: Bool, measurements: [String] = [], policy: WritePolicy = .standard) {
        self.checks = checks
        self.confirmedModel = confirmedModel
        self.unsigned = unsigned
        self.measurements = measurements
        self.policy = policy
    }

    public subscript(_ id: Check.ID) -> Check? { checks.first { $0.id == id } }

    public var requiredPassed: Bool {
        checks.filter { $0.weight == .required }.allSatisfy { $0.status == .passed }
    }

    /// Whether the user may allow experimental writing: an unsigned database outside the
    /// confirmed models, and every required check passed.
    public var allowsExperimentalWriting: Bool { unsigned && !confirmedModel && requiredPassed }

    /// Runs every check. Reads the database, the artwork database and the Music folder;
    /// writes nothing.
    public static func run(on device: IPodDevice, isMusicRunning: () -> Bool = IPodDevice.isMusicRunning) -> Diagnostics {
        var standard = device
        standard.writePolicy = .standard
        let database = try? device.readDatabase()
        let library = database.flatMap { try? ITunesDBParser.parse($0) }
        let checks = [
            usb(device), firmwareDescription(device), identity(device),
            format(device), rebuild(device, database), playCounts(device, library),
            files(device, library), artwork(device),
            volume(device), music(isMusicRunning()),
        ]
        return Diagnostics(checks: checks, confirmedModel: standard.supportsWriting,
                           unsigned: device.format.signing == .presumedUnsigned,
                           measurements: measurements(device, database, library, checks: checks),
                           policy: device.writePolicy)
    }

    /// What the checks add up to, in one line.
    public var verdict: String {
        if confirmedModel { return "Confirmed model: writing allowed." }
        if policy == .developer { return "Developer Mode: writing outside the confirmed models." }
        if allowsExperimentalWriting, policy == .experimental { return "Experimental writing allowed for this iPod (permission given)." }
        if allowsExperimentalWriting {
            return "Every required check passed: experimental writing can be allowed in the app (Settings › Experimental iPods)."
        }
        let failed = checks.filter { $0.weight == .required && $0.status != .passed }.map(\.id.rawValue)
        return unsigned || !failed.isEmpty
            ? "Read-only: \(failed.joined(separator: ", ")) didn't pass."
            : "Read-only: experimental writing covers unsigned databases only."
    }

    /// One line per check, the verdict and the measurements, for the copied report.
    public var reportLines: [String] {
        checks.map { "\($0.group.rawValue)/\($0.id.rawValue): \($0.status.rawValue) - \($0.detail)" }
            + ["verdict: \(verdict)"]
            + (measurements.isEmpty ? [] : ["measurements:"] + measurements.map { "  \($0)" })
    }

    // MARK: - Device

    static func usb(_ device: IPodDevice) -> Check {
        guard let usb = device.usb else {
            return Check(id: .usb, weight: .required, status: .failed, detail: "no USB identity (disk image or unknown connection)")
        }
        let product = String(format: "0x%04X", usb.productID)
        guard let family = usb.familyName, let scheme = usb.expectedScheme else {
            return Check(id: .usb, weight: .required, status: .failed, detail: "\(product) · unknown family")
        }
        let signing = switch scheme {
        case 0: "unsigned family"
        case Hash58.schemeIdentifier: "hash58"
        default: DatabaseFormat.schemeLabel(scheme) ?? "scheme \(scheme)"
        }
        return Check(id: .usb, weight: .required, status: .passed, detail: "\(product) · \(family) · \(signing)")
    }

    static func firmwareDescription(_ device: IPodDevice) -> Check {
        guard let description = device.firmwareDescription else {
            return Check(id: .firmwareDescription, weight: .advisory, status: .warning,
                         detail: "no SysInfoExtended from firmware (common with modified firmware)")
        }
        let formats = description.albumArt.map { String($0.formatID) }.joined(separator: ", ")
        return Check(id: .firmwareDescription, weight: .advisory, status: .passed, detail: [
            "FamilyID \(description.familyID.map(String.init) ?? "?")",
            "firmware \(description.firmwareVersion ?? "?")",
            "artwork formats \(formats.isEmpty ? "none" : formats)",
        ].joined(separator: " · "))
    }

    static func identity(_ device: IPodDevice) -> Check {
        switch device.identityConflict {
        case nil:
            return Check(id: .identity, weight: .required, status: .passed, detail: "USB, firmware and database agree")
        case .usbScheme(let family, let expected, let database):
            return Check(id: .identity, weight: .required, status: .failed,
                         detail: "USB says \(family) (scheme \(expected)), database scheme \(database)")
        case .firmwareGUID:
            // The GUIDs themselves stay out of the report.
            return Check(id: .identity, weight: .required, status: .failed, detail: "firmware GUID differs from the signing key")
        }
    }

    // MARK: - Library

    static func format(_ device: IPodDevice) -> Check {
        let format = device.format
        let header = "header \(format.headerLength) B · version \(String(format: "0x%X", format.version))"
        switch format.signing {
        case .presumedUnsigned:
            return Check(id: .format, weight: .required, status: .passed, detail: "scheme 0 (unsigned) · \(header)")
        case .hash58:
            guard let key = device.fireWireID else {
                return Check(id: .format, weight: .required, status: .failed, detail: "hash58 · signing key not found · \(header)")
            }
            return Check(id: .format, weight: .required, status: .passed, detail: "hash58 · key from \(key.source.rawValue) · \(header)")
        case .unknown(let scheme):
            return Check(id: .format, weight: .required, status: .failed,
                         detail: "scheme \(scheme)\(DatabaseFormat.schemeLabel(scheme).map { " (\($0))" } ?? "") · no signing module · \(header)")
        }
    }

    static func rebuild(_ device: IPodDevice, _ database: Data?) -> Check {
        guard let database else {
            return Check(id: .rebuild, weight: .required, status: .failed, detail: "iTunesDB unreadable")
        }
        do {
            let trip = try RoundTrip.measure(database, fireWireID: device.fireWireID?.bytes)
            return Check(id: .rebuild, weight: .required, status: trip.isIdentical ? .passed : .failed,
                         detail: "rebuilt in memory: \(trip.summary)")
        } catch {
            return Check(id: .rebuild, weight: .required, status: .failed, detail: "rebuild failed: \(error)")
        }
    }

    /// The firmware writes Play Counts after every database it loads, so the file is the
    /// normal state. What matters is whether the writer can merge it: entries one per song,
    /// in the layout measured on hardware.
    static func playCounts(_ device: IPodDevice, _ library: ITLibrary?) -> Check {
        do {
            guard let counts = try device.readPlayCounts() else {
                return Check(id: .playCounts, weight: .advisory, status: .passed, detail: "no Play Counts file")
            }
            let found = "Play Counts: \(counts.entries.count) entries, \(counts.pending.count) with pending statistics"
                + " · \(counts.layoutSummary)"
            if let library, counts.entries.count != library.tracks.count {
                return Check(id: .playCounts, weight: .advisory, status: .warning,
                             detail: "\(found) · \(library.tracks.count) songs in iTunesDB · writes wait")
            }
            guard counts.hasMeasuredLayout else {
                return Check(id: .playCounts, weight: .advisory, status: .warning,
                             detail: "\(found) · layout not measured · experimental writes wait")
            }
            return Check(id: .playCounts, weight: .advisory, status: .passed, detail: "\(found) · merged on write")
        } catch {
            return Check(id: .playCounts, weight: .advisory, status: .warning, detail: "Play Counts unreadable: \(error)")
        }
    }

    // MARK: - Files and artwork

    static func files(_ device: IPodDevice, _ library: ITLibrary?) -> Check {
        guard let library, let report = try? IntegrityReport.build(library: library, paths: device.paths) else {
            return Check(id: .files, weight: .advisory, status: .warning, detail: "not checked: the library didn't parse")
        }
        let counts = [
            "\(report.missingFiles.count) entries without a file",
            "\(report.orphanedFiles.count) files without an entry",
            "\(report.sizeMismatches.count) size mismatches",
            "\(report.danglingReferences.count) dead playlist references",
        ].joined(separator: " · ")
        let synced = report.syncedFiles > 0 ? " · \(report.syncedFiles) files outside iPod_Control, owned by the on-device sync" : ""
        return Check(id: .files, weight: .advisory, status: report.isClean ? .passed : .warning,
                     detail: "\(report.trackCount) entries, \(report.audioFileCount) files · \(counts)\(synced)")
    }

    static func artwork(_ device: IPodDevice) -> Check {
        let artwork: ArtworkLibrary?
        do { artwork = try device.readArtwork() } catch {
            return Check(id: .artwork, weight: .advisory, status: .warning, detail: "ArtworkDB unreadable: \(error)")
        }
        guard let artwork else {
            return Check(id: .artwork, weight: .advisory, status: .info, detail: "no ArtworkDB")
        }
        let formats = artwork.formats.map(\.correlationID)
        let unmeasured = formats.filter { !ConfirmedModels.artworkFormats.contains($0) }.sorted()
        let list = formats.map(String.init).joined(separator: ", ")
        guard unmeasured.isEmpty else {
            return Check(id: .artwork, weight: .advisory, status: .warning,
                         detail: "\(artwork.images.count) images · formats \(list) · \(unmeasured.map(String.init).joined(separator: ", ")) not measured · new artwork disabled")
        }
        return Check(id: .artwork, weight: .advisory, status: .passed, detail: "\(artwork.images.count) images · formats \(list) measured")
    }

    // MARK: - Disk and Mac

    static func volume(_ device: IPodDevice) -> Check {
        let free = ByteCountFormatter.string(fromByteCount: device.volume.availableCapacity, countStyle: .file)
        guard !device.volume.isReadOnly else {
            return Check(id: .volume, weight: .required, status: .failed, detail: "mounted read-only · \(free) free")
        }
        return Check(id: .volume, weight: .required, status: .passed, detail: "writable · \(free) free")
    }

    static func music(_ running: Bool) -> Check {
        running
            ? Check(id: .music, weight: .advisory, status: .warning, detail: "Music is running · writes wait until it quits")
            : Check(id: .music, weight: .advisory, status: .passed, detail: "Music is not running")
    }
}
