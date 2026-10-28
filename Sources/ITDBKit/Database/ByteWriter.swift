import Foundation

/// A record header field: a fixed position and width, little-endian.
///
/// Reading and writing a field go through the same definition, so the offset or
/// width cannot drift apart between the parser and the writer. Record layouts
/// (`MhitLayout` and its neighbors) hold the named fields.
public struct HeaderField<Value: FixedWidthInteger & Sendable>: Sendable {
    public let offset: Int

    public init(_ offset: Int) { self.offset = offset }

    public var size: Int { MemoryLayout<Value>.size }
    public var range: Range<Int> { offset..<(offset + size) }
}

/// Writing little-endian numbers - the counterpart of `ByteReader`.
public enum ByteWriter {

    /// Writes `value` at `offset`. When the field does not fit in the array, it does
    /// nothing and returns `false`: a header shorter than the field (an older database format)
    /// stays untouched.
    @discardableResult
    public static func put<T: FixedWidthInteger>(_ value: T, at offset: Int, in bytes: inout [UInt8]) -> Bool {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= bytes.count else { return false }
        let raw = UInt64(truncatingIfNeeded: value)
        for i in 0..<size { bytes[offset + i] = UInt8(truncatingIfNeeded: raw >> (8 * UInt64(i))) }
        return true
    }

    /// Appends `value` at the end.
    public static func append<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        let raw = UInt64(truncatingIfNeeded: value)
        for i in 0..<MemoryLayout<T>.size { bytes.append(UInt8(truncatingIfNeeded: raw >> (8 * UInt64(i)))) }
    }

    /// The number at `offset`; `nil` when the field does not fit in the array.
    /// A non-throwing read - for header fields that an older format does not have.
    public static func value<T: FixedWidthInteger>(_ type: T.Type, at offset: Int, in bytes: [UInt8]) -> T? {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= bytes.count else { return nil }
        var raw: UInt64 = 0
        for i in 0..<size { raw |= UInt64(bytes[offset + i]) << (8 * UInt64(i)) }
        return T(truncatingIfNeeded: raw)
    }
}

extension Array where Element == UInt8 {
    /// The field value; `nil` when the header is shorter than the field.
    public subscript<T>(field: HeaderField<T>) -> T? {
        ByteWriter.value(T.self, at: field.offset, in: self)
    }

    /// Writes the field value; a header shorter than the field stays untouched.
    @discardableResult
    public mutating func set<T>(_ field: HeaderField<T>, _ value: T) -> Bool {
        ByteWriter.put(value, at: field.offset, in: &self)
    }
}

extension ByteReader {
    /// The field of a record starting at `record`.
    public func value<T>(_ field: HeaderField<T>, inRecordAt record: Int) throws -> T {
        let size = field.size
        guard has((record + field.offset)..<(record + field.offset + size)) else {
            throw ITDBError.readOutOfBounds(offset: record + field.offset, size: size)
        }
        return ByteWriter.value(T.self, at: record + field.offset, in: bytes)!
    }
}
