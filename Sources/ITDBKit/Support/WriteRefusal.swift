import Foundation

/// Why a write to the iPod did not go through.
///
/// Cases the user can do something about are named - the app builds the
/// sentence. The text in `unsupportedArtwork`, `unmergedPlayCounts`
/// and `inconsistent` is a technical detail (format, numbers, condition) - for the
/// diagnostic report and `ipodctl`; from the app the user gets a sentence
/// about what happened, with the detail in parentheses.
public enum WriteRefusal: Sendable, Equatable, CustomStringConvertible {
    /// The iPod is read-only; the device gives the reason when it knows it.
    case readOnly(ReadOnlyReason?)
    /// A condition checked before the write, e.g. Music is running.
    case preflight(WritePreflight.Issue)
    /// The database on the iPod has changed since it was loaded - e.g. Music rewrote it.
    case databaseChanged
    /// The iPod disappeared from its path - unplugged or remounted.
    case deviceGone
    /// A different volume is now at the iPod's path - iPods swapped names.
    case deviceSwapped
    /// Another process is already writing to this iPod (Clickwill or `ipodctl`).
    case anotherWriter
    /// Not enough space - on the iPod or for the originals on the Mac.
    case notEnoughSpace(needed: Int64, available: Int64, on: SpaceLocation)
    /// The folder for originals is not a folder, or cannot be written to.
    case originalsFolderUnusable(URL)
    /// The file to copy to the iPod is empty.
    case emptySourceFile
    /// The iPod wants artwork in a format we do not write yet.
    case unsupportedArtwork(String)
    /// The iPod holds plays that cannot be merged safely.
    case unmergedPlayCounts(String)
    /// The database cannot be signed.
    case cannotSign(SigningRefusal)
    /// An experimental device: the database on it no longer rebuilds byte for byte,
    /// so we no longer understand it. The detail is `RoundTrip.summary`.
    case databaseNotReproduced(String)
    /// An internal condition was not met - a technical description.
    case inconsistent(String)

    public var description: String {
        switch self {
        case .readOnly(let reason): "read-only: \(reason.map(String.init(describing:)) ?? "no reason")"
        case .preflight(let issue): "preflight: \(issue)"
        case .databaseChanged: "database digest differs from the one loaded"
        case .deviceGone: "device gone from its mount point"
        case .deviceSwapped: "another volume at the mount point"
        case .anotherWriter: "device lock held by another writer"
        case .notEnoughSpace(let needed, let available, let location): "not enough space \(location): \(needed) bytes needed, \(available) available"
        case .originalsFolderUnusable(let folder): "originals folder unusable: \(folder.lastPathComponent)"
        case .emptySourceFile: "empty source file"
        case .unsupportedArtwork(let detail): "unsupported artwork: \(detail)"
        case .unmergedPlayCounts(let detail): "unmerged play counts: \(detail)"
        case .cannotSign(let refusal): "cannot sign: \(refusal)"
        case .databaseNotReproduced(let detail): "database not reproduced: \(detail)"
        case .inconsistent(let detail): "inconsistent: \(detail)"
        }
    }
}

/// Why the database cannot be signed.
public enum SigningRefusal: Sendable, Equatable, CustomStringConvertible {
    /// hash58 without a FireWire GUID.
    case fireWireIDMissing
    /// An unsigned database, and the device did not confirm that this is its format.
    case unsignedNotConfirmed
    /// A signing scheme we cannot produce.
    case unknownScheme(UInt16)

    public var description: String {
        switch self {
        case .fireWireIDMissing: "hash58 without a FireWire GUID"
        case .unsignedNotConfirmed: "unsigned format not confirmed by the device"
        case .unknownScheme(let scheme): "unknown scheme \(scheme)"
        }
    }
}

/// Where space ran out.
public enum SpaceLocation: Sendable, Equatable, CustomStringConvertible {
    /// On the iPod. `reserve` - space a write always leaves free;
    /// included in what is needed.
    case iPod(reserve: Int64)
    /// For backups of originals on the Mac.
    case originalsFolder

    public var description: String {
        switch self {
        case .iPod(let reserve): "on the iPod (reserve \(reserve) bytes)"
        case .originalsFolder: "for the originals"
        }
    }
}
