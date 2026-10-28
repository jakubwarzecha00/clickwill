import Foundation

/// A file or track that could not be added to the change list, and why.
/// The app builds the sentence; `description` is a technical description.
public struct QueueRefusal: Sendable, CustomStringConvertible {

    public enum Reason: Sendable, CustomStringConvertible {
        /// The iPod will not play this, and it cannot be transcoded (reason from the file check).
        case cannotPlay(String?)
        /// The same file is already waiting on the change list.
        case alreadyQueued
        /// The file is not audio we can read.
        case notAudio
        /// An album without tracks - there is nowhere to take its fields from for a new file.
        case noSongsToMatch
        /// The model command refused.
        case error(any Error)

        public var description: String {
            switch self {
            case .cannotPlay(let reason): "not playable: \(reason ?? "no reason")"
            case .alreadyQueued: "same file already queued"
            case .notAudio: "not readable audio"
            case .noSongsToMatch: "album has no songs"
            case .error(let error): "\(error)"
            }
        }
    }

    /// The track, file or album the refusal concerns.
    public let subject: String
    public let reason: Reason

    public init(_ subject: String, _ reason: Reason) {
        self.subject = subject
        self.reason = reason
    }

    public var description: String { "\(subject): \(reason)" }
}
