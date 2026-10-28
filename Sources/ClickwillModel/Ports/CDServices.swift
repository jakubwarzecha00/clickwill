import Foundation

/// The world outside the model that a disc needs: the drive, the name lookup,
/// the place for ripped files and the memory of the chosen format.
///
/// The app assembles them at launch (real ones or for demo recordings), tests
/// pass fakes. `CDSession` and `AudioCDStore` know neither launch flags
/// nor AppKit.
public struct CDServices: Sendable {

    /// The drive: the discs in it, and ejecting.
    public struct Drive: Sendable {
        public var mounted: @Sendable () -> [AudioCD]
        public var eject: @Sendable (URL) -> Void

        /// The app provides ejecting - the model does not know AppKit.
        public init(mounted: @escaping @Sendable () -> [AudioCD] = { AudioCD.mounted() },
                    eject: @escaping @Sendable (URL) -> Void) {
            self.mounted = mounted
            self.eject = eject
        }
    }

    /// The names and artwork of a disc.
    public struct Lookup: Sendable {
        /// Releases matching the disc. An empty list: the disc is not in the database.
        public var releases: @Sendable (AudioCD) async throws -> [CDRelease]
        public var frontCover: @Sendable (CDRelease) async throws -> Data?

        public init(releases: @escaping @Sendable (AudioCD) async throws -> [CDRelease],
                    frontCover: @escaping @Sendable (CDRelease) async throws -> Data?) {
            self.releases = releases
            self.frontCover = frontCover
        }

        public static let musicBrainz = Lookup(releases: { try await MusicBrainz.lookup($0) },
                                               frontCover: { try await MusicBrainz.frontCover(of: $0) })

        /// A saved MusicBrainz response instead of the network - for website recordings.
        /// Pauses imitate the server's response time, so the recording shows
        /// the lookup and the artwork arriving.
        public static func recorded(response: Data, cover: Data?) -> Lookup {
            Lookup(releases: { disc in
                try? await Task.sleep(for: .milliseconds(1300))
                return try MusicBrainz.releases(fromJSON: response, discID: disc.discID, trackCount: disc.tracks.count)
            }, frontCover: { _ in
                try? await Task.sleep(for: .milliseconds(500))
                return cover
            })
        }
    }

    /// Where and at what pace to rip.
    public struct Ripping: Sendable {
        public var root: URL
        /// A pause after each track (`CDRipper.rip`).
        public var pace: Duration?

        public init(root: URL, pace: Duration? = nil) {
            self.root = root
            self.pace = pace
        }

        /// Music › Clickwill.
        public static let music = Ripping(root: CDRipper.defaultRoot)
        /// Demo recordings: a temporary folder instead of Music, and one-second files
        /// with a pause, so the progress can be seen.
        public static let demo = Ripping(root: FileManager.default.temporaryDirectory.appendingPathComponent("clickwill-demo-rips"),
                                         pace: .milliseconds(450))
    }

    /// The last chosen format - the next disc starts from it.
    public struct FormatMemory: Sendable {
        public var load: @Sendable () -> CDRipper.Format?
        public var save: @Sendable (CDRipper.Format) -> Void

        public init(load: @escaping @Sendable () -> CDRipper.Format?, save: @escaping @Sendable (CDRipper.Format) -> Void) {
            self.load = load
            self.save = save
        }

        public static let key = "cdRipFormat"
        public static let standard = FormatMemory(
            load: { UserDefaults.standard.string(forKey: key).flatMap(CDRipper.Format.init) },
            save: { UserDefaults.standard.set($0.rawValue, forKey: key) })
    }

    public var drive: Drive
    public var lookup: Lookup
    public var ripping: Ripping
    public var formatMemory: FormatMemory

    public init(drive: Drive, lookup: Lookup = .musicBrainz, ripping: Ripping = .music,
                formatMemory: FormatMemory = .standard) {
        self.drive = drive
        self.lookup = lookup
        self.ripping = ripping
        self.formatMemory = formatMemory
    }
}
