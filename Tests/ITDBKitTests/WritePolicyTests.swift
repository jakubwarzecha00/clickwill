import Foundation
import Testing
@testable import ITDBKit

/// Who may write outside the models confirmed on hardware: the gate in `IPodDevice`
/// and the extra care the writer takes on an experimental device.
@Suite("Write policy")
struct WritePolicyTests {

    /// An unsigned fake in a temporary folder: a database without a scheme, as on pre-2007 iPods.
    struct Rig {
        let root: URL
        let paths: IPodPaths
        let store: SnapshotStore

        func device(_ usb: USBIdentity?, policy: WritePolicy, signing: DatabaseFormat.Signing = .presumedUnsigned) -> IPodDevice {
            IPodDevice(volume: IPodVolume(paths: paths, name: "iPod", totalCapacity: 1, availableCapacity: 1, isReadOnly: false),
                       fireWireID: nil, format: DatabaseFormat(headerLength: 244, version: 117, databaseID: 7, signing: signing),
                       model: IPodModel(modelNumber: nil, name: "iPod", source: .databaseOnly),
                       usb: usb, writePolicy: policy)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    static func unsignedDatabase() throws -> Data {
        var bytes = [UInt8](ITunesDBWriter.serialize(try LibraryFixture.standard()))
        bytes[0x30] = 0; bytes[0x31] = 0
        return Data(bytes)
    }

    /// A database with 4 bytes after the last section that the header counts in: the parser
    /// accepts it, the writer recalculates the length and drops them - it doesn't rebuild exactly.
    static func paddedDatabase() throws -> Data {
        var bytes = [UInt8](try unsignedDatabase()) + [1, 2, 3, 4]
        let total = UInt32(bytes.count)
        withUnsafeBytes(of: total.littleEndian) { bytes.replaceSubrange(8..<12, with: $0) }
        return Data(bytes)
    }

    static func rig(database: Data? = nil) throws -> Rig {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("policy-\(UUID().uuidString)", isDirectory: true)
        let paths = IPodPaths(mountPoint: root.appendingPathComponent("iPod", isDirectory: true))
        try FileManager.default.createDirectory(at: paths.iTunesDB.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (database ?? unsignedDatabase()).write(to: paths.iTunesDB)
        return Rig(root: root, paths: paths, store: SnapshotStore(root: root.appendingPathComponent("Backups", isDirectory: true)))
    }

    static let video = USBIdentity(productID: 0x1209)

    /// Music closed, whatever runs on the machine that tests.
    static var quiet: WriteOptions {
        var options = WriteOptions()
        options.isMusicRunning = { false }
        return options
    }

    @Test("standard: an iPod Video stays read-only, as in 0.4.0")
    func standardKeepsTheFamilyList() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let device = rig.device(Self.video, policy: .standard)
        #expect(!device.supportsWriting)
        #expect(device.readOnlyReason == .unsignedRefused(.familyNotConfirmed))
    }

    @Test("experimental: the family list goes, USB stays")
    func experimentalNeedsUSB() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let video = rig.device(Self.video, policy: .experimental)
        #expect(video.supportsWriting)
        #expect(video.writesOutsideConfirmedModels)
        #expect(video.signer.format.signing == .presumedUnsigned)
        #expect(!rig.device(nil, policy: .experimental).supportsWriting, "a disk image has no USB")
        #expect(rig.device(nil, policy: .experimental).readOnlyReason == .unsignedRefused(.usbNotConfirmed))
    }

    @Test("developer: a disk image without USB can be written")
    func developerWritesDiskImages() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let image = rig.device(nil, policy: .developer)
        #expect(image.supportsWriting)
        #expect(image.writesOutsideConfirmedModels)
    }

    @Test("no policy lifts an identity conflict, an unknown scheme or hash58 without a key")
    func hardRulesStay() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        for policy in [WritePolicy.experimental, .developer] {
            let conflicted = rig.device(USBIdentity(productID: 0x1261), policy: policy)
            #expect(!conflicted.supportsWriting, "\(policy): USB says hash58, the database is unsigned")
            #expect(!rig.device(Self.video, policy: policy, signing: .unknown(2)).supportsWriting, "\(policy): hash72")
            #expect(!rig.device(USBIdentity(productID: 0x1261), policy: policy, signing: .hash58).supportsWriting, "\(policy): no key")
        }
    }

    @Test("a confirmed model under another policy is not outside the lists")
    func confirmedModelStaysConfirmed() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        var nano = rig.device(USBIdentity(productID: 0x1260), policy: .experimental)
        nano.firmwareDescription = try DeviceDescription.parse(xml: Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>FamilyID</key><integer>9</integer></dict></plist>
            """.utf8))
        #expect(nano.supportsWriting)
        #expect(!nano.writesOutsideConfirmedModels)
    }

    @Test("experimental: the writer writes a database that rebuilds byte for byte")
    func experimentalWritesUnderstoodDatabase() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let device = rig.device(Self.video, policy: .experimental)
        var library = try device.readLibrary()
        let first = try #require(library.tracks.first)
        library = library.mappingTracks { $0.uniqueID == first.uniqueID ? $0.setting(.title, to: "Renamed") : $0 }
        let result = try device.writeDatabase(library, using: rig.store, options: Self.quiet)
        #expect(!result.identicalToPrevious)
        #expect(try device.readLibrary().tracks.first?.title == "Renamed")
    }

    @Test("experimental: a database that doesn't rebuild exactly is refused before the backup")
    func experimentalRefusesNotUnderstoodDatabase() throws {
        let rig = try Self.rig(database: try Self.paddedDatabase()); defer { rig.cleanUp() }
        let device = rig.device(Self.video, policy: .experimental)
        let library = try device.readLibrary()
        #expect {
            try device.writeDatabase(library, using: rig.store, options: Self.quiet)
        } throws: { error in
            guard case ITDBError.writeRefused(.databaseNotReproduced(let detail)) = error else { return false }
            return detail.contains("size differs")
        }
        #expect(try rig.store.list(deviceGUID: device.identity).isEmpty, "no backup for a refused write")

        let developer = rig.device(nil, policy: .developer)
        #expect(throws: Never.self, "developer mode takes the risk") {
            try developer.writeDatabase(library, using: rig.store, options: Self.quiet)
        }
    }

    /// mhdp with one entry per track; the first track has `plays` new plays.
    static func playCounts(tracks: Int, header: Int = 0x60, entry: Int = 28, plays: UInt32 = 0) -> Data {
        var counts = Data("mhdp".utf8)
        for value in [UInt32(header), UInt32(entry), UInt32(tracks)] { withUnsafeBytes(of: value.littleEndian) { counts.append(contentsOf: $0) } }
        counts.append(Data(count: header - counts.count))
        for index in 0..<tracks {
            var record = Data(count: entry)
            if index == 0 { withUnsafeBytes(of: plays.littleEndian) { record.replaceSubrange(0..<4, with: $0) } }
            counts.append(record)
        }
        return counts
    }

    @Test("experimental: Play Counts in the measured layout is merged and cleared, as on confirmed models")
    func experimentalMergesMeasuredPlayCounts() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let device = rig.device(Self.video, policy: .experimental)
        let library = try device.readLibrary()
        try Self.playCounts(tracks: library.tracks.count, plays: 3).write(to: rig.paths.playCounts)
        #expect(Diagnostics.playCounts(device, library).status == .passed)

        try device.writeDatabase(library, using: rig.store, options: Self.quiet)
        let written = try device.readLibrary()
        #expect(written.tracks[0].playCount == library.tracks[0].playCount + 3)
        #expect(!FileManager.default.fileExists(atPath: rig.paths.playCounts.path), "merged, so cleared")
    }

    @Test("experimental: Play Counts in another layout waits")
    func experimentalWaitsForUnmeasuredPlayCounts() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let device = rig.device(Self.video, policy: .experimental)
        let library = try device.readLibrary()
        try Self.playCounts(tracks: library.tracks.count, entry: 32).write(to: rig.paths.playCounts)
        let check = Diagnostics.playCounts(device, library)
        #expect(check.status == .warning)
        #expect(check.detail.contains("entries 32 B · layout not measured"))
        #expect {
            try device.writeDatabase(library, using: rig.store, options: Self.quiet)
        } throws: { error in
            guard case ITDBError.writeRefused(.unmergedPlayCounts(let detail)) = error else { return false }
            return detail.contains("not measured") && detail.contains("entries 32 B")
        }
    }

    @Test("Play Counts with a different number of entries than songs: writes wait on every policy")
    func playCountsOfAnotherDatabase() throws {
        let rig = try Self.rig(); defer { rig.cleanUp() }
        let device = rig.device(Self.video, policy: .experimental)
        let library = try device.readLibrary()
        try Self.playCounts(tracks: library.tracks.count + 1).write(to: rig.paths.playCounts)
        #expect(Diagnostics.playCounts(device, library).detail.hasSuffix("songs in iTunesDB · writes wait"))
        #expect(throws: ITDBError.self) { try device.writeDatabase(library, using: rig.store, options: Self.quiet) }
    }

    @Test("the round trip names the size and the differing regions")
    func roundTripSummary() throws {
        let database = try Self.unsignedDatabase()
        let same = try RoundTrip.measure(database, fireWireID: nil)
        #expect(same.isIdentical)
        #expect(same.summary == "\(database.count) B, byte-identical")
        #expect(!same.signed)

        let longer = try RoundTrip.measure(try Self.paddedDatabase(), fireWireID: nil)
        #expect(!longer.isIdentical)
        #expect(longer.summary.hasPrefix("size differs"))
    }
}
