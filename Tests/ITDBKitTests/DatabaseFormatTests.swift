import Testing
import Foundation
@testable import ITDBKit

/// Recognizing the database format. This file guards one thing: that a database of an older
/// generation is **never** taken for hash58. A mistake in that direction ends
/// with signing a database that has no signature, i.e. with a device that will not
/// accept it.
@Suite("Database format")
struct DatabaseFormatTests {

    /// An `mhbd` header of the given length and scheme.
    private func header(length: Int, scheme: UInt16?, version: UInt32 = 117,
                        databaseID: UInt64 = 0x59EC98A042E62CD1) -> Data {
        var bytes = [UInt8](repeating: 0, count: max(length, 0x20))
        bytes.replaceSubrange(0..<4, with: Array("mhbd".utf8))
        for i in 0..<4 { bytes[4 + i] = UInt8((UInt32(length) >> (8 * UInt32(i))) & 0xFF) }
        for i in 0..<4 { bytes[0x10 + i] = UInt8((version >> (8 * UInt32(i))) & 0xFF) }
        for i in 0..<8 { bytes[0x18 + i] = UInt8((databaseID >> (8 * UInt64(i))) & 0xFF) }
        if let scheme, bytes.count > Hash58.Layout.hashingSchemeOffset + 1 {
            bytes[Hash58.Layout.hashingSchemeOffset] = UInt8(scheme & 0xFF)
            bytes[Hash58.Layout.hashingSchemeOffset + 1] = UInt8(scheme >> 8)
        }
        return Data(bytes)
    }

    @Test("Classic 7G: a 244-byte header, scheme 1, writing allowed")
    func classic() throws {
        // Measured on a Classic 7G.
        let format = try DatabaseFormat.detect(header: header(length: 244, scheme: 1))
        #expect(format.signing == .hash58)
        #expect(format.headerLength == 244)
        #expect(format.version == 117)
        #expect(format.databaseID == 0x59EC98A042E62CD1)
        #expect(format.isWritable)
    }

    @Test("a header without the scheme field is never hash58, even when a one lies further on")
    func shortHeaderIsNeverHash58() throws {
        // Field 0x30 lies outside a header shorter than 0x32 bytes - what is
        // there already belongs to the first section and must not be read.
        var bytes = [UInt8](header(length: 0x30, scheme: nil, version: 19))
        bytes += [UInt8](repeating: 0, count: 0x80)
        bytes[0x30] = 1      // a trap
        bytes[0x31] = 0

        let format = try DatabaseFormat.detect(header: Data(bytes))
        #expect(format.signing == .presumedUnsigned)
        #expect(format.isWritable == false, "this is the byte that can break a device")
        #expect(format.headerLength == 0x30)
        #expect(format.version == 19)
    }

    @Test("nano 5G: scheme 2 at 0x30 and the hash72 header at 0x72 are not hash58")
    func hash72IsNotHash58() throws {
        // This mistake was in the code once already: the scheme
        // read from 0x72 hit the start of the hash72 signature (`01 00`)
        // and a nano 5G database came out as hash58.
        var bytes = [UInt8](header(length: 244, scheme: 2))
        bytes[0x72] = 1
        bytes[0x73] = 0
        let format = try DatabaseFormat.detect(header: Data(bytes))
        #expect(format.signing == .unknown(2))
        #expect(format.isWritable == false)
        #expect(format.name.contains("hash72"))
    }

    @Test("a Classic with a hash72 signature next to it: field 0x30 decides")
    func classicWithHash72Blob() throws {
        // This is what a database from a real device looks like: 0x30 = 1, at 0x72 a hash72
        // signature starting with `01 00`, 0x70 = 3.
        var bytes = [UInt8](header(length: 244, scheme: 1))
        bytes[0x70] = 3
        bytes[0x72] = 1
        bytes[0x74] = 0xD7
        #expect(try DatabaseFormat.detect(header: Data(bytes)).signing == .hash58)
    }

    @Test("scheme 0 is an unsigned database, also in a long header")
    func schemeZeroIsUnsigned() throws {
        var bytes = [UInt8](header(length: 244, scheme: 0))
        bytes[0x72] = 1      // the old-style trap
        let format = try DatabaseFormat.detect(header: Data(bytes))
        #expect(format.signing == .presumedUnsigned)
        #expect(format.isWritable == false)
    }

    @Test("an unknown scheme means read-only mode, giving the number")
    func unknownScheme() throws {
        let format = try DatabaseFormat.detect(header: header(length: 244, scheme: 7))
        #expect(format.signing == .unknown(7))
        #expect(format.isWritable == false)
        // Signing refuses with the scheme number - the app tells it to the user.
        do {
            _ = try DatabaseSigner(format: format, fireWireID: nil).sign(Data(count: 300))
            Issue.record("a database with an unknown scheme was signed")
        } catch ITDBError.writeRefused(.cannotSign(.unknownScheme(7))) {
        }
    }

    @Test("the database identifier is read from a short header too")
    func databaseIDAlwaysRead() throws {
        // It serves as the device identity where there is no FireWire GUID,
        // so it must work precisely for older generations.
        let format = try DatabaseFormat.detect(header: header(length: 0x68, scheme: nil,
                                                              databaseID: 0x1122334455667788))
        #expect(format.databaseID == 0x1122334455667788)
    }

    @Test("someone else's file drops out on the signature")
    func rejectsForeignFile() {
        var bytes = [UInt8](repeating: 0, count: 0x40)
        bytes.replaceSubrange(0..<4, with: Array("mhsd".utf8))
        #expect(throws: ITDBError.self) { try DatabaseFormat.detect(header: Data(bytes)) }
    }
}

/// The signing module. A format not confirmed on hardware must **throw**, not
/// guess - a wrongly signed database is worse than an unwritten one.
@Suite("Signing module")
struct DatabaseSignerTests {

    private let guid: [UInt8] = [0x00, 0x0A, 0x27, 0x00, 0x11, 0x22, 0x33, 0x44]

    private func format(_ signing: DatabaseFormat.Signing) -> DatabaseFormat {
        DatabaseFormat(headerLength: 244, version: 117, databaseID: 1, signing: signing)
    }

    @Test("a format without confirmation refuses to sign")
    func refusesUnconfirmed() {
        for signing in [DatabaseFormat.Signing.presumedUnsigned, .unknown(9)] {
            let signer = DatabaseSigner(format: format(signing), fireWireID: guid)
            #expect(throws: ITDBError.self) { try signer.sign(Data(repeating: 0, count: 300)) }
            #expect(throws: ITDBError.self) { try signer.verify(Data(repeating: 0, count: 300)) }
        }
    }

    @Test("hash58 without a GUID refuses, instead of signing with anything")
    func refusesWithoutKey() {
        let signer = DatabaseSigner(format: format(.hash58), fireWireID: nil)
        #expect(throws: ITDBError.self) { try signer.sign(Data(repeating: 0, count: 300)) }
    }

    @Test("the signature to show does not pretend to exist")
    func honestSignatureLabel() throws {
        let unsigned = DatabaseSigner(format: format(.presumedUnsigned), fireWireID: nil)
        #expect(try unsigned.storedSignatureHex(in: Data()) == "(unsigned)")
    }
}
