import Foundation

/// An open iPod: the volume, its database format and whether writing to it is allowed at all.
///
/// The GUID is **optional**. Only the hash58 signature needs it; older iPods
/// do not have one and do not need it, yet their library can still be read.
/// Tying reading to the GUID locked whole generations of devices out before they were even
/// opened.
public struct IPodDevice: Sendable {
    public let volume: IPodVolume
    public let fireWireID: FireWireGUID.Resolved?
    /// What this device's database is - read from the database itself.
    public let format: DatabaseFormat
    /// Which iPod this is. Recognized once, when opened: reading `SysInfo`
    /// on every interface redraw would be I/O inside the drawing
    /// loop. For display, not for deciding about writes.
    public let model: IPodModel
    /// USB product identifier - the second source of the expected signature.
    /// `nil` when the registry did not provide it (for example a disk image instead of an iPod).
    public var usb: USBIdentity? = nil
    /// The description given by the firmware (VPD pages). `nil` when reading failed
    /// (for example a disk image instead of an iPod).
    public var firmwareDescription: DeviceDescription? = nil
    /// A GUID found in a file on the iPod, but rejected because it does not sign
    /// its database - a sentence for the user on why writing is blocked.
    public var rejectedFireWireID: RejectedFireWireID? = nil
    /// Who allows writing outside the confirmed lists. Chosen by the app or `ipodctl`,
    /// never read from the device.
    public var writePolicy: WritePolicy = .standard
    /// The GUID an earlier connection read together with this database (`DeviceAliasStore`).
    /// The registry doesn't give the USB serial number on every connection (nano 2G),
    /// and without it the same iPod came out as another device.
    public var rememberedIdentity: String? = nil

    /// A mismatch between sources that blocks writing: the USB family versus the database
    /// scheme, or the firmware GUID versus the GUID we would sign the database with.
    public var identityConflict: IdentityConflict? {
        if let conflict = usb?.conflict(withDatabaseScheme: hashingScheme) { return conflict }
        if let stated = firmwareDescription?.fireWireGUID, let used = fireWireID?.hex, stated != used {
            return .firmwareGUID(stated: stated, used: used)
        }
        return nil
    }

    public var paths: IPodPaths { volume.paths }

    /// Signing scheme; zero when the header does not have this field.
    public var hashingScheme: UInt16 {
        switch format.signing {
        case .hash58: return Hash58.schemeIdentifier
        case .presumedUnsigned: return 0
        case .unknown(let scheme): return scheme
        }
    }

    /// A stable device name for backups and the order intent.
    /// The GUID when there is one; otherwise the database identifier at `mhbd` 0x18, which
    /// lies in a file we read anyway.
    public var identity: String {
        if let fireWireID { return fireWireID.hex }
        if let rememberedIdentity { return rememberedIdentity }
        return databaseIdentity
    }

    /// From the database identifier: the identity of an iPod whose GUID was never read.
    public var databaseIdentity: String { String(format: "DB-%016llX", format.databaseID) }

    /// Every name this iPod's data on the Mac may be filed under, `identity` first. Before
    /// 0.4.1 a connection without the GUID filed backups and permissions under the database
    /// identity, so both are read.
    public var identities: [String] { identity == databaseIdentity ? [identity] : [identity, databaseIdentity] }

    /// Writing is allowed only for formats **confirmed on
    /// hardware**. An unknown or unconfirmed format means read-only
    /// mode - no exceptions and no attempts.
    public var supportsWriting: Bool {
        guard !volume.isReadOnly, identityConflict == nil else { return false }
        switch format.signing {
        case .hash58: return fireWireID != nil
        case .presumedUnsigned: return unsignedWriteRefusal == nil
        case .unknown: return false
        }
    }

    /// Why this iPod may not be written to; `nil` when it may.
    public var readOnlyReason: ReadOnlyReason? {
        if volume.isReadOnly { return .volumeReadOnly }
        if let conflict = identityConflict { return .identityConflict(conflict) }
        switch format.signing {
        case .hash58:
            guard fireWireID == nil else { return nil }
            return rejectedFireWireID.map(ReadOnlyReason.fireWireIDRejected) ?? .fireWireIDMissing
        case .presumedUnsigned:
            return unsignedWriteRefusal.map(ReadOnlyReason.unsignedRefused)
        case .unknown(let scheme):
            return .unsupportedScheme(scheme)
        }
    }

    /// Families (FamilyID from the firmware description) that find a track's artwork by
    /// the track itself (`mhii` 0x14 = the track's `persistentID`), not through the image owner
    /// and `mhit` 0x160 as the Classic does. nano 2G (9), firmware 1.1.3, measured: one image
    /// record per album showed the artwork only for the owner track.
    public static let artworkByTrackFamilies: Set<Int> = [9]

    /// Whether every track needs its own image record to show artwork during playback.
    public var findsArtworkByTrack: Bool {
        firmwareDescription?.familyID.map(Self.artworkByTrackFamilies.contains) ?? false
    }

    /// Families (FamilyID from the firmware description) on which we write an unsigned
    /// database. nano 2G (9): the database from Finder measured - scheme 0,
    /// empty signature fields, USB 0x1260.
    public static let unsignedWriteFamilies: Set<Int> = [9]

    /// An unsigned database has nothing to defend itself against a mistake with: a missing signature
    /// looks the same on a nano 2G and in a file copied by hand from another iPod.
    /// That is why two confirmations independent of the database are needed - the family
    /// from USB and the family from the firmware. Missing either means a refusal.
    ///
    /// `experimental` keeps USB and drops the family list: the user allowed this device after
    /// diagnostics. `developer` drops both, so a disk image can be written in tests.
    public var unsignedWriteRefusal: UnsignedRefusal? {
        guard format.signing == .presumedUnsigned, writePolicy != .developer else { return nil }
        guard let usb, usb.expectedScheme == 0 else { return .usbNotConfirmed }
        guard writePolicy == .standard else { return nil }
        guard let family = firmwareDescription?.familyID, Self.unsignedWriteFamilies.contains(family) else {
            return .familyNotConfirmed
        }
        return nil
    }

    /// Whether this device writes only because the policy lifted a list - an
    /// unconfirmed family. On such a device the writer takes extra care.
    public var writesOutsideConfirmedModels: Bool {
        guard writePolicy != .standard, format.signing == .presumedUnsigned else { return false }
        var standard = self
        standard.writePolicy = .standard
        return standard.unsignedWriteRefusal != nil
    }

    public static func open(_ volume: IPodVolume) throws -> IPodDevice {
        guard FileManager.default.fileExists(atPath: volume.paths.iTunesDB.path) else {
            throw ITDBError.pathMissing(volume.paths.iTunesDB)
        }
        let header = try readHeader(of: volume.paths.iTunesDB)
        let format = try DatabaseFormat.detect(header: header)
        let usb = USBIdentity.read(mountPoint: volume.mountPoint)
        let firmwareDescription = DeviceDescription.read(mountPoint: volume.mountPoint)
        // A missing GUID is not a read error - it is a missing signing key.
        var fireWireID = try? FireWireGUID.resolve(for: volume)
        var rejected: RejectedFireWireID?
        // The GUID from the USB registry comes from the device itself. A GUID from a file on disk
        // may have come from another iPod (a copied folder, a restored backup),
        // so before we sign with it, it must sign the current database.
        if format.signing == .hash58, let found = fireWireID, found.source != .ioRegistry,
           !FireWireGUID.signs(found.bytes, try Data(contentsOf: volume.paths.iTunesDB)) {
            rejected = RejectedFireWireID(source: found.source, hex: found.hex)
            fireWireID = nil
        }
        return IPodDevice(
            volume: volume,
            fireWireID: fireWireID,
            format: format,
            model: IPodModel.detect(paths: volume.paths, format: format, usb: usb),
            usb: usb,
            firmwareDescription: firmwareDescription,
            rejectedFireWireID: rejected
        )
    }

    public static func openFirst() throws -> IPodDevice {
        try open(try IPodVolume.requireFirst())
    }

    /// Loads the whole database. At 2.5 MB there is no point in complicating it.
    public func readDatabase() throws -> Data {
        try Data(contentsOf: paths.iTunesDB)
    }

    /// Loads and parses the whole library.
    public func readLibrary() throws -> ITLibrary {
        try ITunesDBParser.parse(try readDatabase())
    }

    /// Artwork. `nil` if the device has none.
    public func readArtwork() throws -> ArtworkLibrary? {
        guard FileManager.default.fileExists(atPath: paths.artworkDB.path) else { return nil }
        return try ArtworkDBParser.parse(try Data(contentsOf: paths.artworkDB))
    }

    /// Statistics the iPod has counted since the last sync.
    /// `nil` if the file does not exist - normal on a freshly restored device.
    public func readPlayCounts() throws -> PlayCounts? {
        guard FileManager.default.fileExists(atPath: paths.playCounts.path) else { return nil }
        return try PlayCounts.parse(try Data(contentsOf: paths.playCounts))
    }

    /// Compares the database with what actually lies on disk.
    public func checkIntegrity() throws -> IntegrityReport {
        try IntegrityReport.build(library: try readLibrary(), paths: paths)
    }

    /// Gate: whether the signature stored in the database matches what we compute ourselves.
    /// `nil` when this database is not signed at all.
    public func verifySignature() throws -> Hash58.VerificationResult? {
        guard format.signing == .hash58, let fireWireID else { return nil }
        return try Hash58.verify(database: try readDatabase(), fireWireID: fireWireID.bytes)
    }

    /// Reads only the header - no need to pull in the whole database to learn the scheme.
    private static func readHeader(of url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        // We read as much as the longest known header needs, but
        // require only what every database has: the signature, the length, the version
        // and the identifier. Older generations have a header shorter than 244
        // bytes, and rejecting them here locked them out of recognition.
        let minimum = 0x20
        guard let header = try handle.read(upToCount: Hash58.Layout.minimumLength),
              header.count >= minimum
        else {
            throw ITDBError.databaseTooSmall(bytes: 0, needed: minimum)
        }
        return header
    }
}
