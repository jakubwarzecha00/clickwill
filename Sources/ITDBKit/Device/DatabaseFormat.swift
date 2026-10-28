import Foundation

/// What the database in hand is - read **from the database itself**,
/// not from the device model.
///
/// This distinction is deliberate and it is the most important thing here. The model name
/// comes from `SysInfo`, where it may be missing or our table may be out of date;
/// a mistake there is a typo on screen. The decision "whether and how to sign the write"
/// must not depend on such a source, because a mistake in **it** ends with a database
/// the device will not accept. That is why the format is read from the `mhbd` header.
///
/// Measured on an iPod Classic 7G: the `mhbd` header
/// is 244 bytes, the version at 0x10 is 117, the scheme at 0x30 is 1,
/// a twenty-byte hash58 signature lies at 0x58, and at 0x72 - a hash72 signature,
/// which Music writes alongside, although the Classic does not check it.
///
/// Scheme numbers (field 0x30) according to libgpod: 0 - unsigned
/// (models before 2007), 1 - hash58 (Classic, nano 3G/4G), 2 - hash72
/// (nano 5G), 4 - hashAB (nano 6G/7G). Only 1 is confirmed on hardware.
public struct DatabaseFormat: Sendable, Hashable {

    /// How the database is signed.
    public enum Signing: Sendable, Hashable {
        /// HMAC-SHA1 at 0x58, key from the FireWire GUID. Models from 2007 on.
        /// **Confirmed on hardware.**
        case hash58
        /// Scheme 0, or a header too short to have this field at all - i.e.
        /// a device from before 2007. Databases of these models are not signed,
        /// but **we have not confirmed this with a write**, so that is not enough
        /// to write.
        case presumedUnsigned
        /// The scheme field exists and carries a value we do not know.
        case unknown(UInt16)
    }

    /// Length of the `mhbd` header - the first thing that tells generations apart.
    public let headerLength: Int
    /// Database version at 0x10.
    public let version: UInt32
    /// Database identifier at 0x18. It also serves as the device identity where
    /// there is no FireWire GUID.
    public let databaseID: UInt64
    public let signing: Signing

    /// The smallest header that **fits** the scheme field at 0x30.
    /// A shorter header means the field is absent - not that it should be read
    /// from whatever happens to lie further on in the file.
    public static let schemeFieldEnd = Hash58.Layout.hashingSchemeOffset + 2

    /// Whether we can write this format.
    ///
    /// The default answer is **no**. A format we have not confirmed
    /// on hardware is read-only - even when we know what it should
    /// look like. In this project the difference between "we know" and "we checked" is
    /// worth a device.
    /// The database alone does not settle this for an unsigned format - there the
    /// device decides (`IPodDevice.supportsWriting`).
    public var isWritable: Bool { signing == .hash58 }


    /// Short format name for the interface.
    public var name: String {
        switch signing {
        case .hash58: return "hash58"
        case .presumedUnsigned: return "unsigned"
        case .unknown(let scheme): return Self.schemeLabel(scheme) ?? "scheme \(scheme)"
        }
    }

    /// Names of schemes we know from descriptions, but not from our own writes.
    public static func schemeLabel(_ scheme: UInt16) -> String? {
        switch scheme {
        case 2: return "hash72, iPod nano 5th generation"
        case 4: return "hashAB, iPod nano 6th/7th generation"
        default: return nil
        }
    }

    /// Reads the format from the database header.
    ///
    /// Order matters: **first** the header length, only then
    /// the scheme - we do not read fields beyond the header, because the first
    /// section already lies there. The scheme is only field 0x30; the area at 0x72 is the hash72
    /// signature, and its first bytes (`01 00`) merely pretend to be a one.
    public static func detect(header: Data) throws -> DatabaseFormat {
        guard header.count >= 0x20 else {
            throw ITDBError.databaseTooSmall(bytes: header.count, needed: 0x20)
        }
        let base = header.startIndex
        guard Array(header[base..<(base + 4)]) == Array("mhbd".utf8) else {
            throw ITDBError.unexpectedSignature(
                expected: "mhbd",
                found: String(decoding: header[base..<(base + 4)], as: UTF8.self), offset: 0)
        }
        let bytes = [UInt8](header)
        let headerLength = Int(bytes[RecordLayout.headerLength] ?? 0)
        let version = bytes[MhbdLayout.version] ?? 0
        let databaseID = bytes[MhbdLayout.databaseID] ?? 0

        // The scheme field must fit both in the header and in what we read.
        guard headerLength >= schemeFieldEnd, header.count >= schemeFieldEnd else {
            return DatabaseFormat(headerLength: headerLength, version: version,
                                  databaseID: databaseID, signing: .presumedUnsigned)
        }
        let scheme = bytes[MhbdLayout.hashingScheme] ?? 0
        let signing: Signing
        switch scheme {
        case 0: signing = .presumedUnsigned
        case Hash58.schemeIdentifier: signing = .hash58
        default: signing = .unknown(scheme)
        }
        return DatabaseFormat(headerLength: headerLength, version: version, databaseID: databaseID,
                              signing: signing)
    }
}

/// The module responsible for signing the database of a given generation.
///
/// This is where the line between "we can read" and "we may write" runs. The database
/// writer does not call `Hash58` directly - it gets the module chosen for the format that
/// actually lies in the file. Adding another generation means adding a branch here,
/// without touching the write path, its gates and backups.
///
/// A module we have not confirmed on hardware **throws** instead of guessing.
/// A wrongly signed database is worse than an unwritten one: the device rejects
/// the first entirely, the second simply never came to be.
public struct DatabaseSigner: Sendable {
    public let format: DatabaseFormat
    private let fireWireID: [UInt8]?
    /// Whether the device confirmed that an unsigned database is its format
    /// (`IPodDevice.unsignedWriteRefusal`). The absence of a signature in the file
    /// does not prove it.
    private let unsignedConfirmed: Bool

    public init(format: DatabaseFormat, fireWireID: [UInt8]?, unsignedConfirmed: Bool = false) {
        self.format = format
        self.fireWireID = fireWireID
        self.unsignedConfirmed = unsignedConfirmed
    }

    /// Signs the assembled database. Throws when we cannot sign this format.
    public func sign(_ database: Data) throws -> Data {
        switch format.signing {
        case .hash58:
            guard let fireWireID else {
                throw ITDBError.writeRefused(.cannotSign(.fireWireIDMissing))
            }
            return try Hash58.sign(database, fireWireID: fireWireID)
        case .presumedUnsigned:
            guard unsignedConfirmed else {
                throw ITDBError.writeRefused(.cannotSign(.unsignedNotConfirmed))
            }
            // Nothing to sign; we only make sure assembling did not introduce a scheme.
            guard try Self.scheme(of: database) == 0 else {
                throw ITDBError.writeRefused(.inconsistent("the built library carries a signing scheme, but it was meant to be unsigned"))
            }
            return database
        case .unknown(let scheme):
            throw ITDBError.writeRefused(.cannotSign(.unknownScheme(scheme)))
        }
    }

    /// Whether the signature in the finished database matches its content. For an
    /// unsigned database: whether it is still unsigned.
    public func verify(_ database: Data) throws -> Bool {
        switch format.signing {
        case .hash58:
            guard let fireWireID else { return false }
            return try Hash58.verify(database: database, fireWireID: fireWireID).matches
        case .presumedUnsigned:
            guard unsignedConfirmed else {
                throw ITDBError.writeRefused(.cannotSign(.unsignedNotConfirmed))
            }
            return try Self.scheme(of: database) == 0
        case .unknown(let scheme):
            throw ITDBError.writeRefused(.cannotSign(.unknownScheme(scheme)))
        }
    }

    /// Scheme at 0x30; zero when the header is too short to have this field.
    private static func scheme(of database: Data) throws -> UInt16 {
        let format = try DatabaseFormat.detect(header: database)
        switch format.signing {
        case .presumedUnsigned: return 0
        case .hash58: return Hash58.schemeIdentifier
        case .unknown(let scheme): return scheme
        }
    }

    /// The signature stored in the database, to show in the write result.
    public func storedSignatureHex(in database: Data) throws -> String {
        switch format.signing {
        case .hash58:
            return try Hash58.storedSignature(in: database).hexString
        case .presumedUnsigned:
            return "(unsigned)"
        case .unknown(let scheme):
            return "(scheme \(scheme))"
        }
    }
}

extension IPodDevice {
    /// The signing module chosen for what this device's database is.
    public var signer: DatabaseSigner {
        DatabaseSigner(format: format, fireWireID: fireWireID?.bytes,
                       unsignedConfirmed: format.signing == .presumedUnsigned && unsignedWriteRefusal == nil)
    }
}
