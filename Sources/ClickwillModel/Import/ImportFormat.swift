import Foundation
import ITDBKit

/// The format files go onto the iPod in, chosen in the add sheet.
///
/// The choice changes only what is written to the iPod. The user's own files on the Mac stay
/// as they are.
public enum ImportFormat: String, CaseIterable, Sendable, Identifiable {
    /// The file's own verdict: whatever the iPod plays stays, the rest is converted.
    case automatic
    /// Lossless files the database can describe stay as they are, even outside the iPod's limits.
    case original
    case appleLossless
    case aac256
    case aac128

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .original: return "Keep Original"
        case .appleLossless: return "Apple Lossless"
        case .aac256: return "AAC 256 kbps"
        case .aac128: return "AAC 128 kbps"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            return "Only files your iPod can't play are converted."
        case .original:
            return "FLAC and high-resolution files are copied as they are, and your iPod may skip them. Anything else is converted only if your iPod can't play it."
        case .appleLossless:
            return "Lossless files become Apple Lossless. MP3 and AAC stay as they are, because converting them wouldn't improve the sound."
        case .aac256:
            return "Sounds like the CD to almost everyone, at a fraction of the size. Smaller MP3 and AAC files stay as they are."
        case .aac128:
            return "The smallest files, good for a full iPod nano. Smaller MP3 and AAC files stay as they are."
        }
    }

    /// The candidate with this format applied. `fileVerdict` is the file's own verdict, kept
    /// separately so that a format can be changed back. A rejected file stays rejected.
    public func applied(to candidate: AudioImport.Candidate, fileVerdict: AudioCompatibility.Verdict,
                        on device: IPodCapabilities) -> AudioImport.Candidate {
        var result = candidate
        result.verdict = verdict(for: candidate, fileVerdict: fileVerdict, on: device)
        result.mayBeSkipped = self == .original && !fileVerdict.isSupported && result.verdict.isSupported
        return result
    }

    private func verdict(for candidate: AudioImport.Candidate, fileVerdict: AudioCompatibility.Verdict,
                         on device: IPodCapabilities) -> AudioCompatibility.Verdict {
        if case .rejected = fileVerdict { return fileVerdict }
        let draft = candidate.draft
        switch self {
        case .automatic:
            return fileVerdict
        case .original:
            return candidate.sourceKind?.isLossless == true ? .supported : fileVerdict
        case .appleLossless:
            // Lossy audio in a lossless container only takes more space.
            guard draft.kind.isLossless, !(fileVerdict.isSupported && draft.kind == .appleLossless) else { return fileVerdict }
            return chosen(device.losslessTarget(sampleRate: draft.sampleRate == 0 ? 44_100 : Int(draft.sampleRate)))
        case .aac256:
            return aac(bitRate: 256_000, for: draft, fileVerdict: fileVerdict)
        case .aac128:
            return aac(bitRate: 128_000, for: draft, fileVerdict: fileVerdict)
        }
    }

    /// A playable lossy file at or below the target rate stays: encoding it again would lose
    /// quality without saving space. An unknown rate counts as below.
    private func aac(bitRate: Int, for draft: TrackDraft, fileVerdict: AudioCompatibility.Verdict) -> AudioCompatibility.Verdict {
        if fileVerdict.isSupported, !draft.kind.isLossless, Int(draft.bitRate) * 1000 <= bitRate { return fileVerdict }
        return chosen(.aac(bitRate: bitRate))
    }

    private func chosen(_ target: AudioCompatibility.Target) -> AudioCompatibility.Verdict {
        .convertible(reason: "\(label) was chosen", target: target)
    }
}
