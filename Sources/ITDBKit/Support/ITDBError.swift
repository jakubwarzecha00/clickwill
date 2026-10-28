import Foundation

public enum ITDBError: Error, CustomStringConvertible, Sendable {
    case noIPodFound
    case notAnITunesDB
    case databaseTooSmall(bytes: Int, needed: Int)
    case invalidFireWireID(String)
    case fireWireIDUnavailable(volume: String)
    case unsupportedHashingScheme(UInt16)
    case signatureMismatch(stored: String, computed: String)
    case snapshotNotFound(String)
    case snapshotCorrupted(snapshot: String, file: String)
    case snapshotIncomplete(missing: String)
    case pathMissing(URL)
    case readOutOfBounds(offset: Int, size: Int)
    case unexpectedSignature(expected: String, found: String, offset: Int)
    case lengthMismatch(declared: Int, actual: Int)
    case writeRefused(WriteRefusal)
    case writeVerificationFailed(reason: String)
    /// A path from iPod or backup data points outside the allowed folder.
    /// The path itself is left out of the description - it goes into the diagnostic report.
    case unsafePath(String)

    public var description: String {
        switch self {
        case .noIPodFound: "no iPod found"
        case .notAnITunesDB: "not an iTunesDB"
        case .databaseTooSmall(let bytes, let needed): "iTunesDB too short: \(bytes) bytes, at least \(needed) needed"
        case .invalidFireWireID(let value): "invalid FireWire GUID \"\(value)\""
        case .fireWireIDUnavailable(let volume): "FireWire GUID of \(volume) unavailable"
        case .unsupportedHashingScheme(let scheme): "unsupported hashing scheme \(scheme)"
        case .signatureMismatch(let stored, let computed): "signature mismatch: stored \(stored), computed \(computed)"
        case .snapshotNotFound(let id): "backup \(id) not found"
        case .snapshotCorrupted(let snapshot, let file): "backup \(snapshot): \(file) doesn't match its checksum"
        case .snapshotIncomplete(let missing): "backup incomplete: \(missing) missing"
        case .pathMissing(let url): "missing \(url.lastPathComponent)"
        case .readOutOfBounds(let offset, let size): "read out of bounds: \(size) bytes at \(offset)"
        case .unexpectedSignature(let expected, let found, let offset): "expected \(expected) at \(offset), found \(found)"
        case .lengthMismatch(let declared, let actual): "length mismatch: \(declared) declared, \(actual) found"
        case .writeRefused(let refusal): "write refused: \(refusal)"
        case .writeVerificationFailed(let reason): "verification failed: \(reason)"
        case .unsafePath: "unsafe path in library data"
        }
    }
}

extension Data {
    /// Hexadecimal form, used wherever we compare signatures.
    public var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
