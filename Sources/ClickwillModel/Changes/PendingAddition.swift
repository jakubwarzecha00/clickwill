import Foundation
import CoreGraphics
import ImageIO
import ITDBKit

/// A track waiting to be added. The file is still on the Mac - it reaches the iPod
/// only on "Write to iPod", together with the rest of the changes.
public struct PendingAddition: Identifiable, Sendable {
    public let id: UUID
    public var draft: TrackDraft
    public let source: URL
    /// The source format verdict. Conversion, if needed, happens during the write -
    /// the original stays untouched on the Mac, so there is nothing to ask about.
    public let verdict: AudioCompatibility.Verdict
    public let formatLabel: String
    /// Where to get artwork for this track's album. Used only when
    /// the album is new - we do not replace an existing album's artwork when adding
    /// a song, because nobody asked for that.
    public let cover: AudioImport.CoverSource?
    /// A place in a specific album (adding from the album view). Without it the track
    /// goes where its tags point.
    public var placement: AlbumPlacement?

    public init(id: UUID, draft: TrackDraft, source: URL, verdict: AudioCompatibility.Verdict,
                formatLabel: String, cover: AudioImport.CoverSource?) {
        self.id = id
        self.draft = draft
        self.source = source
        self.verdict = verdict
        self.formatLabel = formatLabel
        self.cover = cover
    }

    public init(_ candidate: AudioImport.Candidate) {
        self.init(id: candidate.id, draft: candidate.draft, source: candidate.url,
                  verdict: candidate.verdict, formatLabel: candidate.formatLabel,
                  cover: candidate.coverSource)
    }

    public var needsConversion: Bool { !verdict.isSupported }
    public var target: AudioCompatibility.Target? {
        if case .convertible(_, let target) = verdict { return target }
        return nil
    }
    /// A file we can neither play nor transcode.
    public var isHopeless: Bool {
        if case .rejected = verdict { return true }
        return false
    }
}
