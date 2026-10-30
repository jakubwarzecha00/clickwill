import Foundation

/// Whether the writer reproduces a database byte for byte - the measure of whether we
/// understand a given device's library. Parsing and assembling can be checked on every
/// generation, before any of them gets a write module.
public struct RoundTrip: Sendable {
    public let original: Data
    public let rebuilt: Data
    /// Whether the rebuilt bytes carry a signature. A database we cannot sign is compared
    /// without one: an unsigned one has nothing to sign, an unknown scheme cannot be signed.
    public let signed: Bool

    /// Parses `original`, assembles it again and signs it the way the format in the file
    /// says. hash58 needs the device key.
    public static func measure(_ original: Data, fireWireID: [UInt8]?) throws -> RoundTrip {
        let library = try ITunesDBParser.parse(original)
        let format = try DatabaseFormat.detect(header: original)
        let serialized = ITunesDBWriter.serialize(library)
        guard format.signing == .hash58 else {
            return RoundTrip(original: original, rebuilt: serialized, signed: false)
        }
        guard fireWireID != nil else { throw ITDBError.writeRefused(.cannotSign(.fireWireIDMissing)) }
        let signed = try DatabaseSigner(format: format, fireWireID: fireWireID).sign(serialized)
        return RoundTrip(original: original, rebuilt: signed, signed: true)
    }

    public var isIdentical: Bool { original == rebuilt }

    /// Continuous areas where the bytes differ, within the common length.
    /// `limit` stops the scan on a database that differs everywhere.
    public func differingRegions(limit: Int = 4096) -> [Range<Int>] {
        let a = [UInt8](original), b = [UInt8](rebuilt)
        var regions: [Range<Int>] = []
        var counted = 0
        for index in 0..<min(a.count, b.count) where a[index] != b[index] {
            if let last = regions.last, last.upperBound == index {
                regions[regions.count - 1] = last.lowerBound..<(index + 1)
            } else {
                regions.append(index..<(index + 1))
            }
            counted += 1
            if counted >= limit { break }
        }
        return regions
    }

    /// A short technical summary for the diagnostic report and refusals.
    public var summary: String {
        if isIdentical { return "\(original.count) B, byte-identical" }
        if original.count != rebuilt.count {
            return "size differs: \(original.count) B original, \(rebuilt.count) B rebuilt"
        }
        let regions = differingRegions()
        let bytes = regions.reduce(0) { $0 + $1.count }
        return "\(bytes) B differ in \(regions.count) regions of \(original.count) B"
    }
}
