import Foundation

/// The kind of an audio file as the iPod database understands it.
///
/// The `mhit` record describes the format in four places at once, and all of them must
/// agree, because each is read by someone else: the four-character code (`MhitLayout.fileTypeCode`,
/// the container name), `MhitLayout.mpegFlag` (1 only for MP3), `MhitLayout.losslessFlag` (0x02000000
/// for lossless formats) and the text description in an `mhod` of type 6, which the iPod
/// shows in the track info.
///
/// Values measured on a real device across 1603 tracks: within
/// one text description all three numeric fields are constant, and between
/// descriptions they differ. That is why a new record must be created
/// from a template of **the same kind**, not from any record.
public enum TrackFileKind: String, Sendable, CaseIterable, Codable {
    case mp3
    case aac
    case appleLossless
    case wav

    /// The container code (`MhitLayout.fileTypeCode`). It lies reversed in the file (little endian).
    public var fourCharacterCode: String {
        switch self {
        case .mp3: return "MP3 "
        case .aac, .appleLossless: return "M4A "
        case .wav: return "WAV "
        }
    }

    /// The description in an `mhod` of type 6. We deliberately use only the variants without store traces:
    /// "Purchased" and "Matched" carry additional DRM flags (0x94-0x97, 0x195,
    /// 0x1EC, 0x229), which must not be faked for one's own file.
    public var fileTypeDescription: String {
        switch self {
        case .mp3: return "MPEG audio file"
        case .aac: return "AAC audio file"
        case .appleLossless: return "Apple Lossless audio file"
        case .wav: return "WAV audio file"
        }
    }

    public var isLossless: Bool {
        switch self {
        case .appleLossless, .wav: return true
        case .mp3, .aac: return false
        }
    }

    public var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .aac, .appleLossless: return "m4a"
        case .wav: return "wav"
        }
    }

    /// The kind derived from the CoreAudio identifier and the extension.
    /// `nil` for anything the iPod does not know - such files go through
    /// conversion, not straight into the database.
    public static func from(formatID: String, fileExtension: String) -> TrackFileKind? {
        switch formatID {
        case ".mp3": return .mp3
        case "alac": return .appleLossless
        case "lpcm": return fileExtension.lowercased() == "wav" ? .wav : nil
        default: return formatID.hasPrefix("aac") ? .aac : nil
        }
    }

    /// The `MhitLayout.losslessFlag` value for Apple Lossless.
    static let losslessFlagValue: UInt32 = 0x0200_0000

    /// The four-character code as a number: the first character in the most significant byte,
    /// so in the file (little endian) it lies reversed.
    var fourCharacterValue: UInt32 {
        fourCharacterCode.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}

extension ITTrack {

    /// The kind read from the record - by the text description, because only it tells
    /// AAC from Apple Lossless (both are in the M4A container).
    public var fileKind: TrackFileKind? {
        TrackFileKind.allCases.first { $0.fileTypeDescription == fields[.fileType] }
    }

    /// Sets all four fields describing the format at once.
    ///
    /// A separate method precisely so that one cannot be changed without
    /// the others: a mismatch between them is silent - the iPod keeps playing, and the file
    /// is described as something it is not.
    public func settingFileKind(_ kind: TrackFileKind) -> ITTrack {
        var copy = self
        copy.rawHeader.set(MhitLayout.fileTypeCode, kind.fourCharacterValue)
        copy.rawHeader.set(MhitLayout.mpegFlag, kind == .mp3 ? 1 : 0)
        copy.rawHeader.set(MhitLayout.losslessFlag, kind.isLossless ? TrackFileKind.losslessFlagValue : 0)
        return copy.setting(.fileType, to: kind.fileTypeDescription)
    }
}

/// File kind bytes beyond the four places set by `settingFileKind`.
///
/// A template of the same kind is always the first choice. The profile is for
/// an iPod that does not have such a track yet - a nano 2G after Finder has only
/// MP3. Then the record is created from a record of **the same iPod** of another kind,
/// and the profile switches the bytes that carry the kind.
///
/// Measured on a Classic 7G, on records written by Music (added before
/// Clickwill): 62 ALAC and 1364 MP3. The profile holds bytes outside the fields the
/// generator sets itself that are constant in ALAC and differ from MP3, or vary in MP3:
/// - 0x90 = 60 (MP3: 12) and 0x20C = 0 (MP3: 2) - in 60 of 62 ALAC records,
///   the two outliers are single tracks from other albums;
/// - fields in which MP3 carries encoder data and ALAC constant zeros (0x40, 0x7A,
///   0xB0, 0xB8-0xB9, 0xC4-0xC9, 0xCF, 0xDC-0xDF, 0xF8-0xFB, 0x102, 0x197,
///   0x1E4-0x1E7, 0x1F0-0x1F3, 0x24C), 0xCC = 1 and 0x134-0x137 = 0x80.
/// Device-dependent fields (0x124, 0x1E0) stay from the iPod's record.
///
/// Confirmed on the device: the nano 2G plays albums copied by Clickwill,
/// including ALAC built from an MP3 record and this profile.
public struct TrackKindProfile: Sendable {
    public let kind: TrackFileKind
    public let bytes: [Int: UInt8]

    public static let appleLossless: TrackKindProfile = {
        var bytes: [Int: UInt8] = [0x90: 60, 0x20C: 0, 0xCC: 1]
        let zeros = [0x40, 0x7A, 0xB0, 0xB8, 0xB9, 0xCF, 0x102, 0x197, 0x24C]
            + Array(0xC4...0xC9) + Array(0xDC...0xDF) + Array(0xF8...0xFB)
            + Array(0x1E4...0x1E7) + Array(0x1F0...0x1F3)
        for offset in zeros { bytes[offset] = 0 }
        for offset in 0x134...0x137 { bytes[offset] = 0x80 }
        return TrackKindProfile(kind: .appleLossless, bytes: bytes)
    }()

    /// Kinds with a measured profile.
    public static let measured: [TrackFileKind: TrackKindProfile] = [.appleLossless: appleLossless]
}
