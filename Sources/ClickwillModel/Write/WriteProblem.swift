import Foundation

/// Something the write did not do, even though the rest went in: what it concerns and why.
///
/// The app builds the sentence for the user (the post-write report). `description`
/// is a technical description for `ipodctl`; only the reason (`reason`) goes into the
/// diagnostic report, without titles from the library.
public struct WriteProblem: Sendable, CustomStringConvertible {

    public enum Reason: Sendable, CustomStringConvertible {
        /// An error of the core, the model or the system.
        case error(any Error)
        /// The file after conversion is still not suitable for this iPod.
        case stillNotPlayable
        /// The track was added, but not where it was dropped in the album.
        case notPlaced(any Error)
        /// The deletion rule does not touch the old file (a folder, a link,
        /// something outside the iPod's music folder).
        case keptByRule
        /// The old file could not be deleted.
        case notDeleted(any Error)

        public var description: String {
            switch self {
            case .error(let error): "\(error)"
            case .stillNotPlayable: "converted file still not playable"
            case .notPlaced(let error): "added, not placed: \(error)"
            case .keptByRule: "not a deletable audio file under Music"
            case .notDeleted(let error): "not deleted: \(error)"
            }
        }
    }

    /// The track, album or file the problem concerns.
    public let subject: String
    public let reason: Reason

    public init(_ subject: String, _ reason: Reason) {
        self.subject = subject
        self.reason = reason
    }

    public var description: String { "\(subject): \(reason)" }
}
