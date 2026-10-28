import Foundation

/// A write blocked by the app state, not by the iPod - the iPod's refusals
/// are carried by `ITDBError.writeRefused`.
public enum WriteBlocked: Error, Equatable, CustomStringConvertible {
    /// A demo copy (`--demo`): nothing reaches the iPod.
    case demoCopy
    /// The library does not come from a connected iPod or is not fully loaded.
    case notFromDevice

    public var description: String {
        switch self {
        case .demoCopy: "writes blocked: demo copy"
        case .notFromDevice: "writes blocked: library not from a connected iPod"
        }
    }
}
