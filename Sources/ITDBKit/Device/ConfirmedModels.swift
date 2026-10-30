import Foundation

/// What Clickwill writes only because it was measured on a real iPod - the one place a new
/// model is confirmed. Each entry carries its evidence; a change here needs the same evidence
/// (CONTRIBUTING.md: the diagnostic report, the byte-for-byte rebuild and a test on the iPod).
///
/// A model that is not listed opens read-only under the standard policy. Its owner can still
/// allow it in Settings › Experimental iPods once every required diagnostic check passes
/// (`WritePolicy.experimental`), which is how the evidence for an entry here is gathered.
///
/// Signed databases are confirmed by their signature instead (`DatabaseFormat`, `Hash58`):
/// a database Clickwill can sign the way the iPod checks it is written on any model.
public enum ConfirmedModels {

    /// Firmware families (FamilyID in the firmware description) whose **unsigned** database is
    /// written under the standard policy. The USB product must also be an unsigned family
    /// (`USBIdentity`); two confirmations independent of the database, because a missing
    /// signature looks the same on every iPod.
    ///
    /// - 9, iPod nano (2nd generation), firmware 1.1.3, USB 0x1260: the database from Finder
    ///   measured (scheme 0, empty signature fields); editing, adding with artwork, changing
    ///   artwork, deleting and restoring a backup checked on the iPod.
    public static let unsignedWriteFamilies: Set<Int> = [9]

    /// Firmware families that look a track's artwork up by the track itself (`mhii` 0x14 = the
    /// track's `persistentID`), not through the image owner and `mhit` 0x160 as the iPod classic
    /// does. Every song of an album then needs its own image record (`trackImageShares`).
    ///
    /// - 9, iPod nano (2nd generation), firmware 1.1.3: one image record per album showed the
    ///   artwork only for the owner track.
    public static let artworkByTrackFamilies: Set<Int> = [9]

    /// Artwork formats (`FormatId`) whose pixel encoding was measured: RGB565 little-endian.
    /// Dimensions and slot sizes are read from the device; only the encoding is confirmed here.
    ///
    /// - 1055, 1060, 1061: iPod classic 7G.
    /// - 1027 (100x100), 1031 (42x42): iPod nano (2nd generation), described as L565 by its
    ///   firmware; 1027 seen on the Now Playing screen, 1031 written in the same file and read by
    ///   the iPod.
    public static let artworkFormats: Set<UInt32> = [1027, 1031, 1055, 1060, 1061]

    /// `Play Counts` layouts merged on a model outside the confirmed ones (`PlayCounts`).
    ///
    /// - header 0x60, entries 28 B: iPod nano (2nd generation), firmware 1.1.3.
    public static let playCountsLayouts: Set<PlayCountsLayout> = [PlayCountsLayout(header: 0x60, entry: 28)]

    public struct PlayCountsLayout: Hashable, Sendable {
        public let header: Int
        public let entry: Int

        public init(header: Int, entry: Int) {
            self.header = header
            self.entry = entry
        }
    }
}
