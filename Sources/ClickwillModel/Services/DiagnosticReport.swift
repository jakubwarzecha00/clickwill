import Foundation
import ITDBKit

/// A report for filing a problem. The app does not connect to the network, so
/// the only way from a tester to us is text they copy and send themselves.
///
/// The report describes the device and the database state - not the person. It contains no GUID
/// or serial number (they identify a specific unit), no iPod name
/// (it is often the owner's name), no paths (they contain the account name) and no track
/// titles. Error texts go through `redacted`, because a write refusal
/// can quote the GUID.
public enum DiagnosticReport {

    /// - Parameters:
    ///   - album: the album the user pointed to in the report themselves -
    ///     the only title that goes into the report.
    ///   - diagnostics: a result already on screen, so the report says what the user saw;
    ///     otherwise the checks run now.
    @MainActor
    public static func text(for model: LibraryModel, appVersion: String, system: String, hardware: String,
                            album: String? = nil, diagnostics: Diagnostics? = nil) -> String {
        var lines = ["Clickwill \(appVersion)", "\(system), \(hardware)", ""]
        // The name given to the iPod usually carries the owner's name ("Anna's iPod") - we cut it too.
        let names = (model.device.map { [$0.volume.name] } ?? []) + [model.library?.deviceName].compactMap { $0 }
        func redacted(_ text: String) -> String { DiagnosticReport.redacted(text, names: names) }
        if let device = model.device {
            let description = device.firmwareDescription
            lines += [
                "iPod: \(device.model.name)\(device.model.modelNumber.map { " (\($0))" } ?? "") [\(device.model.source.rawValue)]",
                "USB product: \(device.usb.map { String(format: "0x%04X", $0.productID) } ?? "not read")",
                "Firmware: family \(description?.familyID.map(String.init) ?? "?"), "
                    + "version \(description?.firmwareVersion ?? "?"), "
                    + "artwork formats \(description.map { $0.albumArt.map { String($0.formatID) }.joined(separator: " ") } ?? "?")",
                "Database: \(device.format.name), \(device.format.headerLength)-byte header, version \(device.format.version)",
                "Signing key: \(signingKey(device))",
                "Identity: \(identitySource(device))",
                "Writing: \(device.supportsWriting ? "allowed" : "refused: \(redacted(device.readOnlyReason?.description ?? "no reason given"))")",
                "Write policy: \(device.writePolicy)\(device.writesOutsideConfirmedModels ? ", unconfirmed model" : "")",
                "Volume: \(device.volume.isReadOnly ? "read-only" : "writable"), "
                    + "\(gigabytes(device.volume.usedCapacity)) used of \(gigabytes(device.volume.totalCapacity))",
            ]
            // The same checks as the Diagnostics sheet - technical, without a GUID.
            lines += ["Diagnostics:"] + ((diagnostics ?? model.runDiagnostics())?.reportLines.map { "  " + redacted($0) } ?? [])
            if let grant = model.permissions.grant(for: device) {
                lines.append("Experimental permission: since \(grant.allowedAt.formatted(.iso8601.year().month().day())), "
                             + "last answer \(grant.lastAnswer.map { $0 ? "changes visible" : "changes not visible" } ?? "none")")
            }
            if let preflight = model.preflight() {
                lines.append("Preflight: " + (preflight.isClear ? "clear" : preflight.issues.map { redacted($0.description) }.joined(separator: "; ")))
            }
        } else if model.source != nil {
            lines.append("Source: backup (no iPod connected)")
        } else {
            lines.append("No iPod connected")
        }
        lines += [
            "Library: \(model.albums.count) albums, \(model.trackCount) songs, "
                + "\(model.albums.reduce(0) { $0 + $1.missingFiles }) entries without a file, "
                + "\(model.artwork?.images.count ?? 0) artwork entries",
            "Pending changes: \(model.changes.log.count)",
        ]
        if let library = model.library {
            let health = ArtworkHealth.check(
                library: library, artwork: model.artwork,
                artworkDB: model.paths.flatMap { try? model.environment.files.contents(of: $0.artworkDB) },
                paths: model.device != nil ? model.paths : nil, files: model.environment.files)
            lines += health.summary
            if let album {
                let songs = library.tracks.filter { ($0.album ?? "") == album }
                lines += ["", "Album chosen by the user: \(album) (\(songs.count) songs)"] + health.details(forAlbum: album)
            }
        }
        lines += model.lastWriteSummary.map(redacted)
        if case .failed(let failure) = model.state { lines.append("Load failure: \(redacted(failure.description))") }
        if let failure = model.lastWriteFailure { lines.append("Last write failure: \(redacted(failure))") }
        return lines.joined(separator: "\n")
    }

    /// Cuts unit identifiers (16 hex characters - the GUID) out of the text,
    /// along with user paths and the given names (the iPod name is often a person's name).
    /// Also the whole path in the home folder (security audit 0.1.3)
    /// and the names of music, artwork and image files - only the fact that they were there remains.
    public static func redacted(_ text: String, names: [String] = []) -> String {
        var result = text.replacingOccurrences(of: #"(?i)\b(0x)?[0-9a-f]{16}\b"#, with: "<GUID>", options: .regularExpression)
        result = result.replacingOccurrences(of: #"/Users/[^/]+"#, with: "~", options: .regularExpression)
        result = result.replacingOccurrences(of: #"/Volumes/[^/]+"#, with: "/Volumes/<iPod>", options: .regularExpression)
        // The default name "iPod" says nothing about the owner, and cutting it
        // would break every "iPod classic" in the text.
        for name in names where !name.isEmpty && name.caseInsensitiveCompare("iPod") != .orderedSame {
            result = result.replacingOccurrences(of: name, with: "<iPod name>")
        }
        // To the end of the line or the quote: folders with spaces in their names
        // otherwise left their tail behind.
        result = result.replacingOccurrences(of: #"~/[^\n"'“”]*"#, with: "<path in your home folder>", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"[^\s/"'“”(]+\.(?i:mp3|m4a|m4p|m4b|aac|flac|wav|aiff?|ithmb|jpe?g|png|heic)\b"#,
            with: "<file>", options: .regularExpression)
        return result
    }

    /// Where the GUID came from - without the GUID itself.
    /// An unsigned database needs no key - "not found" there read as a fault.
    static func signingKey(_ device: IPodDevice) -> String {
        if let found = device.fireWireID { return "found (\(origin(found.source)))" }
        return device.format.signing == .hash58 ? "not found" : "not needed (unsigned database)"
    }

    /// Where the name the Mac files this iPod under came from (`DeviceAliasStore`), without the GUID.
    static func identitySource(_ device: IPodDevice) -> String {
        if let found = device.fireWireID { return "GUID (\(origin(found.source)))" }
        if device.rememberedIdentity != nil { return "GUID remembered from an earlier connection, not read on this one" }
        return "database identifier (no GUID read on this Mac)"
    }

    static func origin(_ source: FireWireGUID.Source) -> String {
        switch source {
        case .ioRegistry: return "USB registry"
        case .sysInfoExtended: return "SysInfoExtended file"
        case .sysInfo: return "SysInfo file"
        }
    }

    static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}
