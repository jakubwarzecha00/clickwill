import Foundation

/// Why the iPod may not be written to. The cases carry data (model, GUID,
/// scheme); the app builds the sentence for the user. `description` is a technical
/// description for `ipodctl` and the diagnostic report.
public enum ReadOnlyReason: Sendable, Hashable, CustomStringConvertible {
    /// macOS mounted the volume read-only.
    case volumeReadOnly
    /// Identity sources disagree (USB, firmware, database scheme, GUID).
    case identityConflict(IdentityConflict)
    /// A GUID found in a file, but it does not sign this iPod's database.
    case fireWireIDRejected(RejectedFireWireID)
    /// Without a GUID the database cannot be signed (hash58).
    case fireWireIDMissing
    /// An unsigned database without two independent confirmations of the family.
    case unsignedRefused(UnsignedRefusal)
    /// A signing scheme we cannot produce.
    case unsupportedScheme(UInt16)

    public var description: String {
        switch self {
        case .volumeReadOnly: "volume mounted read-only"
        case .identityConflict(let conflict): "identity conflict: \(conflict)"
        case .fireWireIDRejected(let rejected): "rejected \(rejected)"
        case .fireWireIDMissing: "FireWire GUID missing"
        case .unsignedRefused(let refusal): "unsigned database refused: \(refusal)"
        case .unsupportedScheme(let scheme): "signature scheme \(scheme) not supported"
        }
    }
}

/// A mismatch between identity sources that blocks writing.
public enum IdentityConflict: Sendable, Hashable, CustomStringConvertible {
    /// The USB family uses a different signing scheme than the database.
    case usbScheme(family: String, expected: UInt16, database: UInt16)
    /// The GUID from the firmware description differs from the one we would sign the database with.
    case firmwareGUID(stated: String, used: String)

    public var description: String {
        switch self {
        case .usbScheme(let family, let expected, let database): "USB says \(family) (scheme \(expected)), database scheme \(database)"
        case .firmwareGUID(let stated, let used): "firmware GUID \(stated), signing GUID \(used)"
        }
    }
}

/// Why we refuse to write an unsigned database.
public enum UnsignedRefusal: Sendable, Hashable, CustomStringConvertible {
    /// USB does not confirm an unsigned model.
    case usbNotConfirmed
    /// The firmware does not give a family on which writing is confirmed.
    case familyNotConfirmed

    public var description: String {
        switch self {
        case .usbNotConfirmed: "USB doesn't confirm an unsigned model"
        case .familyNotConfirmed: "firmware family not confirmed for unsigned writes"
        }
    }
}

/// A GUID from a file on the iPod that does not sign its database.
public struct RejectedFireWireID: Sendable, Hashable, CustomStringConvertible {
    public let source: FireWireGUID.Source
    public let hex: String

    public init(source: FireWireGUID.Source, hex: String) {
        self.source = source
        self.hex = hex
    }

    public var description: String { "GUID \(hex) from \(source.rawValue)" }
}
