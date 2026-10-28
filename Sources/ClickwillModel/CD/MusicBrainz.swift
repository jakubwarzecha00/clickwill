import Foundation

/// A disc release recognized in MusicBrainz.
public struct CDRelease: Sendable, Identifiable, Equatable {
    public struct Track: Sendable, Equatable {
        public let number: Int
        public let title: String
        public let artist: String
        public let durationMilliseconds: UInt32?
    }

    /// The release MBID.
    public let id: String
    public let title: String
    public let artist: String
    /// The year of the album's first release (1995 for Ozzmosis), not of this pressing.
    public let year: UInt32
    /// The year of this particular pressing (a 2002 reissue) - for the description only.
    public let pressingYear: UInt32
    public let country: String?
    public let label: String?
    public let discNumber: Int
    public let totalDiscs: Int
    /// The artist "Various Artists" - on the iPod the album goes to compilations.
    public let isCompilation: Bool
    public let hasFrontCover: Bool
    public let tracks: [Track]
    /// The genre with the most votes ("Heavy Metal"), if anyone set one.
    public var genre: String? = nil

    /// One line for choosing a release: country, year, label.
    public var summary: String {
        var parts: [String] = []
        if let country, !country.isEmpty { parts.append(Self.countryName(country)) }
        if pressingYear > 0 { parts.append(String(pressingYear)) }
        if let label, !label.isEmpty { parts.append(label) }
        if totalDiscs > 1 { parts.append("Disc \(discNumber) of \(totalDiscs)") }
        return parts.joined(separator: " · ")
    }

    /// MusicBrainz uses ISO codes and a few of its own: XE is Europe, XW the whole world.
    static func countryName(_ code: String) -> String {
        switch code {
        case "XE": return "Europe"
        case "XW": return "Worldwide"
        case "XU": return code
        default: return Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code
        }
    }
}

/// A disc query to MusicBrainz and an artwork query to the Cover Art Archive.
///
/// The only place apart from updates where Clickwill goes to the network, and only
/// after clicking "Look Up Online". We send just the
/// Disc ID and the list of track lengths - nothing from the library or the iPod.
public enum MusicBrainz {

    public enum LookupError: Error, Equatable, CustomStringConvertible {
        case busy
        case server(Int)
        case unreadableResponse
        case tooLarge

        public var description: String {
            switch self {
            case .busy: "MusicBrainz: rate limited"
            case .server(let status): "MusicBrainz: HTTP \(status)"
            case .unreadableResponse: "MusicBrainz: unreadable response"
            case .tooLarge: "MusicBrainz: response too large"
            }
        }
    }

    /// MusicBrainz requires identifying with a name, a version and a contact.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Clickwill/\(version) ( https://clickwilldev.com )"
    }

    static let various = "89ad4ac3-39f7-470e-963a-56509c546377"

    /// Releases matching the disc. First by Disc ID; when nobody has added this pressing
    /// yet, the server itself searches by track lengths (`toc`).
    /// An empty list means: the disc is not in the database.
    public static func lookup(_ disc: AudioCD, session: URLSession = .shared) async throws -> [CDRelease] {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/discid/\(disc.discID)")!
        components.queryItems = [
            URLQueryItem(name: "toc", value: disc.tocQuery),
            URLQueryItem(name: "cdstubs", value: "no"),
            URLQueryItem(name: "inc", value: "artist-credits labels recordings release-groups genres"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        // `+` in the table is a separator the server must receive literally.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "%2B", with: "+")
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await fetch(request, session: session, limit: jsonLimit)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return try releases(fromJSON: data, discID: disc.discID, trackCount: disc.tracks.count)
        case 404: return []
        case 503: throw LookupError.busy
        default: throw LookupError.server(status)
        }
    }

    /// The release's front cover (500 px - the iPod shows at most 320 anyway).
    /// `nil` when there is none.
    public static func frontCover(of release: CDRelease, session: URLSession = .shared) async throws -> Data? {
        guard release.hasFrontCover,
              let url = URL(string: "https://coverartarchive.org/release/\(release.id)/front-500") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request, session: session, limit: coverLimit)
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        return data
    }

    /// A disc response is a few dozen kilobytes, a 500 px cover a few hundred.
    static let jsonLimit = 5 << 20
    static let coverLimit = 10 << 20

    /// A download with a size limit and redirects only where MusicBrainz and
    /// the Cover Art Archive lead (security audit 0.1.3). A larger response
    /// is cut off midway, instead of being kept whole in memory.
    static func fetch(_ request: URLRequest, session: URLSession, limit: Int) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request, delegate: RedirectPolicy.shared)
        guard response.expectedContentLength <= Int64(limit) else { throw LookupError.tooLarge }
        var data = Data()
        data.reserveCapacity(max(0, Int(response.expectedContentLength)))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw LookupError.tooLarge }
        }
        return (data, response)
    }

    /// Redirects only over HTTPS and only to MusicBrainz and the Cover Art Archive
    /// (the covers physically live on archive.org servers). A rejected redirect
    /// ends with a 3xx response, i.e. no result.
    final class RedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
        static let shared = RedirectPolicy()
        static let hosts = ["musicbrainz.org", "coverartarchive.org", "archive.org"]

        static func allows(_ url: URL?) -> Bool {
            guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            Self.allows(request.url) ? request : nil
        }
    }

    /// The `discid` response in JSON. From each release we take the medium that
    /// holds our disc - a two-disc release has two and only one counts.
    public static func releases(fromJSON data: Data, discID: String, trackCount: Int) throws -> [CDRelease] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LookupError.unreadableResponse
        }
        let releases = root["releases"] as? [[String: Any]] ?? []
        return releases.compactMap { release in
            guard let id = release["id"] as? String else { return nil }
            let media = release["media"] as? [[String: Any]] ?? []
            let medium = media.first { medium in
                (medium["discs"] as? [[String: Any]] ?? []).contains { $0["id"] as? String == discID }
            } ?? media.first { ($0["track-count"] as? Int) == trackCount }
            guard let medium else { return nil }

            let albumArtist = credit(release["artist-credit"])
            let tracks = (medium["tracks"] as? [[String: Any]] ?? []).enumerated().map { index, track in
                let recording = track["recording"] as? [String: Any]
                let title = track["title"] as? String ?? recording?["title"] as? String ?? ""
                let artist = credit(track["artist-credit"] ?? recording?["artist-credit"])
                return CDRelease.Track(number: track["position"] as? Int ?? index + 1, title: title,
                                       artist: artist.isEmpty ? albumArtist : artist,
                                       durationMilliseconds: (track["length"] as? Int).map { UInt32(clamping: $0) })
            }
            // Genres are voted on and usually hang on the album (release group),
            // not on the pressing - we take the one with the most votes.
            let group = release["release-group"] as? [String: Any]
            let votes = (release["genres"] as? [[String: Any]] ?? []).isEmpty
                ? group?["genres"] as? [[String: Any]] ?? [] : release["genres"] as? [[String: Any]] ?? []
            let genre = votes.max { ($0["count"] as? Int ?? 0) < ($1["count"] as? Int ?? 0) }?["name"] as? String
            let artistIDs = (release["artist-credit"] as? [[String: Any]] ?? [])
                .compactMap { ($0["artist"] as? [String: Any])?["id"] as? String }
            let label = (release["label-info"] as? [[String: Any]])?
                .compactMap { ($0["label"] as? [String: Any])?["name"] as? String }.first
            func year(_ date: Any?) -> UInt32 {
                (date as? String)?.firstMatch(of: /^(\d{4})/).flatMap { UInt32($0.1) } ?? 0
            }
            let pressing = year(release["date"])
            let original = year((release["release-group"] as? [String: Any])?["first-release-date"])
            return CDRelease(
                id: id, title: release["title"] as? String ?? "", artist: albumArtist,
                year: original > 0 ? original : pressing, pressingYear: pressing,
                country: release["country"] as? String, label: label,
                discNumber: medium["position"] as? Int ?? 1, totalDiscs: max(1, media.count),
                isCompilation: artistIDs.contains(various),
                hasFrontCover: (release["cover-art-archive"] as? [String: Any])?["front"] as? Bool ?? false,
                tracks: tracks, genre: genre.map { $0.capitalized })
        }
    }

    /// "Ozzy Osbourne", "Jay-Z & Linkin Park" - names together with the join phrases.
    static func credit(_ value: Any?) -> String {
        (value as? [[String: Any]] ?? []).map { part in
            (part["name"] as? String ?? "") + (part["joinphrase"] as? String ?? "")
        }.joined()
    }
}
