import Foundation
import CryptoKit

/// The `hash58` signature - a checksum that the iPod Classic and nano 3G/4G verify
/// at every startup. Without a valid signature the device rejects the database.
///
/// The algorithm is HMAC-SHA1 over the whole `iTunesDB` file, where the key is derived
/// from the device's FireWire GUID: consecutive byte pairs of the GUID go through
/// the least common multiple, and the result through the AES S-boxes.
///
/// It is an integrity checksum the device verifies at startup.
/// It does not protect any track or restrict access to content - the same
/// audio files play regardless of it. The algorithm has been publicly
/// documented since 2007.
///
/// A Swift implementation written from scratch from the algorithm description
/// in libgpod, `src/itdb_hash58.c` (BSD-3-Clause, Copyright (C) 2007
/// Christophe Fergeau <teuf@gnome.org>, based on a proof of concept by wtbw).
/// Full license notice: THIRD-PARTY-NOTICES at the repository root.
/// The tables (AES S-box and inverse S-box) were additionally compared with
/// mono/ipod-sharp `src/Hash58.cs` (LGPL-2) purely as a correctness check -
/// nothing was copied from that file.
///
/// iPod and iTunes are trademarks of Apple. This code is not supported
/// or published by Apple.
public enum Hash58 {

    /// Offsets in the `mhbd` header that the signature concerns.
    public enum Layout {
        /// Signature field, 20 bytes.
        public static let signature = 0x58..<0x6C
        /// Database identifier, zeroed before computing.
        public static let databaseID = 0x18..<0x20
        /// Undocumented block, zeroed before computing.
        public static let unknownBlock = 0x32..<0x46
        /// `UInt16` little-endian: signing scheme number (1 = hash58,
        /// 2 = hash72, 4 = hashAB, 0 = unsigned).
        ///
        /// Not from 0x72: that is where the 46-byte hash72 signature starts, which Music
        /// also writes on the Classic, and its first two bytes are `01 00` -
        /// reading from there yields 1 by accident, and on a nano 5G it would take a
        /// hash72 database for hash58.
        public static let hashingSchemeOffset = 0x30
        /// The hash72 signature (nano 5G; Music writes it on the Classic too, but
        /// the device checks only hash58). We do not touch it.
        public static let hash72Signature = 0x72..<0xA0
        /// Smallest sensible header size.
        public static let minimumLength = 0xF4
    }

    /// Signing scheme number stored at offset `0x30`.
    public static let schemeIdentifier: UInt16 = 1

    // MARK: - Key

    /// Derives 20 bytes of key material from the 8-byte FireWire GUID.
    static func derivedKey(fireWireID: [UInt8]) -> Data {
        precondition(fireWireID.count == 8, "FireWire GUID must be 8 bytes")

        var y = [UInt8](repeating: 0, count: 16)
        for i in 0..<4 {
            let value = leastCommonMultiple(Int(fireWireID[i * 2]), Int(fireWireID[i * 2 + 1]))
            let high = Int((value & 0xFF00) >> 8)
            let low = Int(value & 0xFF)
            y[i * 4 + 0] = table1[high]
            y[i * 4 + 1] = table2[high]
            y[i * 4 + 2] = table1[low]
            y[i * 4 + 3] = table2[low]
        }

        var material = Data(fixedSalt)
        material.append(contentsOf: y)
        return Data(Insecure.SHA1.hash(data: material))
    }

    /// The version from the reference - `Foundation` has no equivalent for the zero case.
    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while true {
            a = a % b
            if a == 0 { return b }
            b = b % a
            if b == 0 { return a }
        }
    }

    static func leastCommonMultiple(_ a: Int, _ b: Int) -> Int {
        (a == 0 || b == 0) ? 1 : (a * b) / greatestCommonDivisor(a, b)
    }

    // MARK: - Signature

    /// Computes the signature for an already prepared database image.
    ///
    /// - Parameter preparedDatabase: bytes after `prepare(_:)` - with the fields zeroed.
    public static func signature(fireWireID: [UInt8], preparedDatabase: Data) -> Data {
        let key = SymmetricKey(data: derivedKey(fireWireID: fireWireID))
        let code = HMAC<Insecure.SHA1>.authenticationCode(for: preparedDatabase, using: key)
        return Data(code)
    }

    /// Zeroes the fields that are not part of the signature and sets the scheme number.
    ///
    /// Order matters: iTunes computes the signature over a database in which these fields
    /// are zeros, and only then writes their real values back.
    public static func prepare(_ database: Data) throws -> Data {
        guard database.count >= Layout.minimumLength else {
            throw ITDBError.databaseTooSmall(bytes: database.count, needed: Layout.minimumLength)
        }
        guard database.prefix(4) == Data("mhbd".utf8) else {
            throw ITDBError.notAnITunesDB
        }
        var bytes = [UInt8](database)
        for range in [Layout.databaseID, Layout.unknownBlock, Layout.signature] {
            for i in range { bytes[i] = 0 }
        }
        bytes[Layout.hashingSchemeOffset] = UInt8(schemeIdentifier & 0xFF)
        bytes[Layout.hashingSchemeOffset + 1] = UInt8(schemeIdentifier >> 8)
        return Data(bytes)
    }

    /// The signature read from the database - the one iTunes wrote.
    public static func storedSignature(in database: Data) throws -> Data {
        guard database.count >= Layout.minimumLength else {
            throw ITDBError.databaseTooSmall(bytes: database.count, needed: Layout.minimumLength)
        }
        return database.subdata(in: Layout.signature)
    }

    /// Signing scheme number stored in the database. `1` is hash58.
    public static func hashingScheme(in database: Data) throws -> UInt16 {
        guard database.count >= Layout.minimumLength else {
            throw ITDBError.databaseTooSmall(bytes: database.count, needed: Layout.minimumLength)
        }
        let low = UInt16(database[database.startIndex + Layout.hashingSchemeOffset])
        let high = UInt16(database[database.startIndex + Layout.hashingSchemeOffset + 1])
        return low | (high << 8)
    }

    /// Writes a freshly computed signature into a copy of the database.
    public static func sign(_ database: Data, fireWireID: [UInt8]) throws -> Data {
        let signature = try self.signature(fireWireID: fireWireID, preparedDatabase: prepare(database))
        var bytes = [UInt8](database)
        for (offset, byte) in zip(Layout.signature, signature) { bytes[offset] = byte }
        bytes[Layout.hashingSchemeOffset] = UInt8(schemeIdentifier & 0xFF)
        bytes[Layout.hashingSchemeOffset + 1] = UInt8(schemeIdentifier >> 8)
        return Data(bytes)
    }

    // MARK: - Verification

    public struct VerificationResult: Sendable {
        public let stored: Data
        public let computed: Data
        public var matches: Bool { stored == computed }
    }

    /// Checks whether the signature in the database matches what we compute ourselves.
    ///
    /// This is a gate: until it returns `matches == true` for an untouched database,
    /// nothing may be written to the device.
    public static func verify(database: Data, fireWireID: [UInt8]) throws -> VerificationResult {
        VerificationResult(
            stored: try storedSignature(in: database),
            computed: try signature(fireWireID: fireWireID, preparedDatabase: prepare(database))
        )
    }
}

// MARK: - Convenience

extension Hash58 {
    /// Converts a GUID given as 16 hex characters into 8 bytes.
    public static func fireWireID(fromHex hex: String) throws -> [UInt8] {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
        guard cleaned.count == 16 else {
            throw ITDBError.invalidFireWireID(cleaned)
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(8)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                throw ITDBError.invalidFireWireID(cleaned)
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
