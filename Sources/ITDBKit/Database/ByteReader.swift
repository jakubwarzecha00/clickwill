import Foundation

/// Reading numbers and text from the database. Everything in `iTunesDB` is little-endian -
/// even on iPods formatted for the Mac, despite what HFS+ suggests.
public struct ByteReader: Sendable {
    public let bytes: [UInt8]

    public init(_ data: Data) { self.bytes = [UInt8](data) }
    public init(_ bytes: [UInt8]) { self.bytes = bytes }

    public var count: Int { bytes.count }

    public func has(_ range: Range<Int>) -> Bool {
        range.lowerBound >= 0 && range.upperBound <= bytes.count
    }

    public func u8(at offset: Int) throws -> UInt8 {
        guard has(offset..<(offset + 1)) else { throw ITDBError.readOutOfBounds(offset: offset, size: 1) }
        return bytes[offset]
    }

    public func u16(at offset: Int) throws -> UInt16 {
        guard has(offset..<(offset + 2)) else { throw ITDBError.readOutOfBounds(offset: offset, size: 2) }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    public func u32(at offset: Int) throws -> UInt32 {
        guard has(offset..<(offset + 4)) else { throw ITDBError.readOutOfBounds(offset: offset, size: 4) }
        var value: UInt32 = 0
        for i in (0..<4).reversed() { value = value << 8 | UInt32(bytes[offset + i]) }
        return value
    }

    public func u64(at offset: Int) throws -> UInt64 {
        guard has(offset..<(offset + 8)) else { throw ITDBError.readOutOfBounds(offset: offset, size: 8) }
        var value: UInt64 = 0
        for i in (0..<8).reversed() { value = value << 8 | UInt64(bytes[offset + i]) }
        return value
    }

    public func slice(_ range: Range<Int>) throws -> [UInt8] {
        guard has(range) else {
            throw ITDBError.readOutOfBounds(offset: range.lowerBound, size: range.count)
        }
        return Array(bytes[range])
    }

    /// Four-character record signature, e.g. `mhit`.
    public func signature(at offset: Int) throws -> String {
        String(decoding: try slice(offset..<(offset + 4)), as: UTF8.self)
    }

    /// UTF-16LE text of the given length in bytes.
    public func utf16String(at offset: Int, byteCount: Int) throws -> String {
        let raw = try slice(offset..<(offset + byteCount))
        var units: [UInt16] = []
        units.reserveCapacity(byteCount / 2)
        for i in stride(from: 0, to: byteCount - 1, by: 2) {
            units.append(UInt16(raw[i]) | UInt16(raw[i + 1]) << 8)
        }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: - Time

public enum MacTime {
    /// Seconds between January 1, 1904 (the Mac epoch) and January 1, 1970.
    public static let epochOffset: TimeInterval = 2_082_844_800

    public static func date(from value: UInt32) -> Date? {
        guard value != 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(value) - epochOffset)
    }

    public static func value(from date: Date?) -> UInt32 {
        guard let date else { return 0 }
        let seconds = date.timeIntervalSince1970 + epochOffset
        guard seconds > 0, seconds <= TimeInterval(UInt32.max) else { return 0 }
        return UInt32(seconds)
    }
}
