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
    /// Which iPods may be written to in this release. The app narrows the scope
    /// to the iPod classic; `ipodctl` and the tests keep all formats
    /// confirmed on hardware.
    public var scope: WriteScope = .confirmedFormats

    /// The caller chooses the write scope - it is a release decision, not a format one:
    /// a format may be confirmed and the model still be out of scope.
    public enum WriteScope: Sendable {
        /// Every format confirmed on hardware.
        case confirmedFormats
        /// Only the iPod classic (6G, 6.5G, 7G), hash58.
        case iPodClassic
    }

    /// The Classic's FamilyID in the firmware description - measured on a 7G.
    public static let classicFamilyID = 11

    /// Whether this is an iPod classic according to the device itself: USB first, then the
    /// firmware description. Neither means "we do not know", so not a Classic.
    public var isIPodClassic: Bool {
        if let usb { return usb.productID == USBIdentity.classicProductID }
        if let family = firmwareDescription?.familyID { return family == Self.classicFamilyID }
        return false
    }

    /// A model outside the write scope the caller chose (`scope`).
    public var isOutsideWriteScope: Bool { scope == .iPodClassic && !isIPodClassic }

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
        return String(format: "DB-%016llX", format.databaseID)
    }

    /// Writing is allowed only for formats **confirmed on
    /// hardware**. An unknown or unconfirmed format means read-only
    /// mode - no exceptions and no attempts.
    public var supportsWriting: Bool {
        guard !volume.isReadOnly, identityConflict == nil, !isOutsideWriteScope else { return false }
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
        if isOutsideWriteScope { return .outsideWriteScope(model: model.name) }
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

    /// Families (FamilyID from the firmware description) on which we write an unsigned
    /// database. nano 2G (9): the database from Finder measured - scheme 0,
    /// empty signature fields, USB 0x1260.
    public static let unsignedWriteFamilies: Set<Int> = [9]

    /// An unsigned database has nothing to defend itself against a mistake with: a missing signature
    /// looks the same on a nano 2G and in a file copied by hand from another iPod.
    /// That is why two confirmations independent of the database are needed - the family
    /// from USB and the family from the firmware. Missing either means a refusal.
    public var unsignedWriteRefusal: UnsignedRefusal? {
        guard format.signing == .presumedUnsigned else { return nil }
        guard let usb, usb.expectedScheme == 0 else { return .usbNotConfirmed }
        guard let family = firmwareDescription?.familyID, Self.unsignedWriteFamilies.contains(family) else {
            return .familyNotConfirmed
        }
        return nil
    }

    /// - Parameter scope: which iPods may be written to (the app: Classic only).
    public static func open(_ volume: IPodVolume, scope: WriteScope = .confirmedFormats) throws -> IPodDevice {
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
            rejectedFireWireID: rejected,
            scope: scope
        )
    }

    public static func openFirst(scope: WriteScope = .confirmedFormats) throws -> IPodDevice {
        try open(try IPodVolume.requireFirst(), scope: scope)
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
