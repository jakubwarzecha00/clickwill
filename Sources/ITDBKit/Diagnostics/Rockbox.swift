import Foundation

/// Rockbox next to Apple's firmware. Rockbox doesn't read iTunesDB: it builds its own
/// database from the tags inside the audio files. Rules below were measured with the
/// Rockbox simulator for the iPod Video (Rockbox `f3ffe78`) and read from its source.
public struct RockboxInstallation: Sendable, Equatable {
    /// `Version:` from `.rockbox/rockbox-info.txt`, e.g. `4.0` or `f3ffe789ef-261030`.
    public let version: String?
    /// `Target:`, e.g. `ipodvideo`.
    public let target: String?

    public init(version: String?, target: String?) {
        self.version = version
        self.target = target
    }

    /// `nil` when the volume has no `.rockbox` folder.
    public static func detect(at mountPoint: URL) -> RockboxInstallation? {
        let folder = mountPoint.appendingPathComponent(".rockbox", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let info = (try? String(contentsOf: folder.appendingPathComponent("rockbox-info.txt"), encoding: .utf8)) ?? ""
        func field(_ name: String) -> String? {
            info.split(whereSeparator: \.isNewline)
                .first { $0.hasPrefix("\(name):") }
                .map { $0.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
        }
        return RockboxInstallation(version: field("Version"), target: field("Target"))
    }
}

/// An image embedded in an audio file, as Rockbox's album art sees it.
public enum RockboxImage: Sendable, Equatable {
    /// Baseline or extended sequential JPEG, 8-bit: Rockbox shows it
    /// (`jpeg_load.c`, SOF0/SOF1; measured: shown on the Now Playing screen).
    case jpeg
    /// Progressive JPEG: found, not shown (`jpeg_load.c` returns -4; measured).
    case progressiveJPEG
    /// Another JPEG coding (lossless, arithmetic, 12-bit): not shown.
    case unsupportedJPEG
    /// PNG: found by the tag parser, not shown - playback decodes JPEG only
    /// (`playback.c`; measured).
    case png
    case other

    public var isShownByRockbox: Bool { self == .jpeg }

    public init(_ data: Data) {
        let bytes = [UInt8](data.prefix(64 * 1024))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { self = .png; return }
        guard bytes.starts(with: [0xFF, 0xD8]) else { self = .other; return }
        // Segments: FF marker, then a big-endian length that counts itself.
        var index = 2
        while index + 4 <= bytes.count {
            guard bytes[index] == 0xFF else { self = .other; return }
            let marker = bytes[index + 1]
            if marker == 0xFF { index += 1; continue }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            switch marker {
            case 0xC0, 0xC1:
                self = index + 4 < bytes.count && bytes[index + 4] == 8 ? .jpeg : .unsupportedJPEG
                return
            case 0xC2, 0xC6, 0xCA, 0xCE:
                self = .progressiveJPEG; return
            case 0xC3, 0xC5, 0xC7, 0xC9, 0xCB, 0xCD, 0xCF:
                self = .unsupportedJPEG; return
            case 0xDA:
                // Image data starts without a frame header - not a JPEG Rockbox can read.
                self = .other; return
            default:
                index += 2 + length
            }
        }
        self = .other
    }
}
