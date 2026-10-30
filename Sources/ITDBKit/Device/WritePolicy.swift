import Foundation

/// Who allows writing to a device outside the lists confirmed on hardware.
///
/// ITDBKit does not know how it was built. The app and `ipodctl` choose the policy and
/// hand it to the device; the gates in `IPodDevice` and the database writer read it from there.
/// Rules that no policy lifts: a signing scheme we cannot produce, hash58 without
/// a key, an identity conflict, a read-only volume, the backup before a write.
public enum WritePolicy: Sendable, Hashable, CustomStringConvertible {
    /// Only what was measured on hardware (`IPodDevice.unsignedWriteFamilies`,
    /// `ArtworkAddition.confirmedFormats`).
    case standard
    /// A model outside the lists, allowed by the user for this one device after every
    /// required diagnostic check passed. USB must still confirm an unsigned family, and
    /// the database must rebuild byte for byte before every write.
    case experimental
    /// A build from source, for testing new models and disk images. Lifts the family
    /// list, the USB confirmation and the list of measured artwork formats.
    case developer

    public var description: String {
        switch self {
        case .standard: "standard"
        case .experimental: "experimental"
        case .developer: "developer"
        }
    }
}
