import Foundation
import Testing
import AVFoundation
import ImageIO
import ITDBKit
@testable import ClickwillModel

@Suite("Audio CD: table of contents, MusicBrainz, ripping")
struct AudioCDTests {

    /// The table of contents of the Ozzmosis disc from the drive: track starts from `.TOC.plist`.
    static let ozzmosisStarts = [150, 26662, 48880, 72170, 101332, 129100, 158865, 182280, 204295, 233825, 255457, 278472]

    static func toc(sessions: [(number: Int, leadout: Int, tracks: [(point: Int, start: Int, data: Bool)])]) -> Data {
        let plist: [String: Any] = ["Sessions": sessions.map { session in
            ["Session Number": session.number, "Leadout Block": session.leadout,
             "First Track": session.tracks.first?.point ?? 1, "Last Track": session.tracks.last?.point ?? 1,
             "Track Array": session.tracks.map { ["Point": $0.point, "Start Block": $0.start, "Data": $0.data,
                                                  "Session Number": session.number] }]
        }]
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    static var ozzmosis: AudioCD {
        let tracks = ozzmosisStarts.enumerated().map { (point: $0.offset + 1, start: $0.element, data: false) }
        let names = (1...12).map { "\($0) Audio Track.aiff" } + [".TOC.plist"]
        return try! AudioCD(tocPlist: toc(sessions: [(1, 299_880, tracks)]),
                            volume: URL(fileURLWithPath: "/Volumes/Audio CD"), fileNames: names)
    }

    @Test("the Disc ID matches the one computed for Ozzmosis")
    func discID() {
        let disc = Self.ozzmosis
        #expect(disc.discID == "MBePQbKQkpdfMDQaZznaB43ChcQ-")
        #expect(disc.tracks.count == 12)
        // drutil gave for track 1: blockcount = 26512.
        #expect(disc.tracks[0].sectorCount == 26_512)
        #expect(disc.tracks[11].sectorCount == 299_880 - 278_472)
        #expect(Int(disc.duration) == 66 * 60 + 38 - 2)
        #expect(disc.tocQuery.hasPrefix("1+12+299880+150+26662+"))
        #expect(disc.tracks[3].file?.lastPathComponent == "4 Audio Track.aiff")
        #expect(disc.fileTitle(of: disc.tracks[0]) == nil)
        #expect(!disc.hasTitle)
    }

    @Test("Enhanced CD: the data track is part of neither the disc nor the Disc ID")
    func enhancedCD() throws {
        let data = Self.toc(sessions: [(1, 200_000, [(1, 150, false), (2, 100_000, false)]),
                                       (2, 260_000, [(3, 211_400, true)])])
        let disc = try AudioCD(tocPlist: data, volume: URL(fileURLWithPath: "/Volumes/X"),
                               fileNames: ["1 Intro.aiff", "2 Song.aiff"])
        #expect(disc.tracks.map(\.number) == [1, 2])
        #expect(disc.tracks[1].sectorCount == 100_000)
        #expect(disc.tocQuery == "1+2+200000+150+100000")
        #expect(disc.fileTitle(of: disc.tracks[1]) == "Song")
        #expect(disc.hasTitle)
    }

    @Test("MusicBrainz response: the medium with our disc, a compilation, the track artist")
    func musicBrainzJSON() throws {
        let json = """
        {"releases":[{"id":"rel-1","title":"Hits","date":"2004-05-01","country":"GB","release-group":{"first-release-date":"1999","genres":[{"name":"hard rock","count":2},{"name":"heavy metal","count":8}]},"genres":[],
          "artist-credit":[{"name":"Various Artists","joinphrase":"","artist":{"id":"89ad4ac3-39f7-470e-963a-56509c546377"}}],
          "label-info":[{"label":{"name":"Sony"}}],"cover-art-archive":{"front":true},
          "media":[
            {"position":1,"track-count":2,"discs":[{"id":"other"}],"tracks":[{"position":1,"title":"A","length":1000},{"position":2,"title":"B"}]},
            {"position":2,"track-count":2,"discs":[{"id":"DISC"}],"tracks":[
              {"position":1,"title":"Numb / Encore","length":205000,"artist-credit":[{"name":"Jay-Z","joinphrase":" & "},{"name":"Linkin Park","joinphrase":""}]},
              {"position":2,"title":"Hey Ya!","artist-credit":[{"name":"OutKast","joinphrase":""}]}]}]}]}
        """
        let releases = try MusicBrainz.releases(fromJSON: Data(json.utf8), discID: "DISC", trackCount: 2)
        let release = try #require(releases.first)
        #expect(release.discNumber == 2 && release.totalDiscs == 2)
        #expect(release.isCompilation && release.hasFrontCover)
        #expect(release.year == 1999 && release.pressingYear == 2004)
        #expect(release.genre == "Heavy Metal")
        #expect(release.tracks[0].artist == "Jay-Z & Linkin Park")
        #expect(release.tracks[0].durationMilliseconds == 205_000)
        #expect(release.summary == "United Kingdom · 2004 · Sony · Disc 2 of 2")
    }

    @Test("a release fills the draft; the track artist only when it differs from the album")
    func applyRelease() {
        var draft = CDDraft(disc: Self.ozzmosis)
        #expect(draft.songs[0].title == "Track 1")
        let tracks = (1...12).map { CDRelease.Track(number: $0, title: "Song \($0)",
                                                     artist: $0 == 5 ? "Ozzy & Lemmy" : "Ozzy Osbourne",
                                                     durationMilliseconds: nil) }
        draft.apply(CDRelease(id: "x", title: "Ozzmosis", artist: "Ozzy Osbourne", year: 1995, pressingYear: 2002, country: "US",
                              label: "Epic", discNumber: 1, totalDiscs: 1, isCompilation: false,
                              hasFrontCover: false, tracks: tracks))
        #expect(draft.album == "Ozzmosis" && draft.year == "1995")
        #expect(draft.songs[11].title == "Song 12")
        #expect(draft.songs[0].artist == "")
        #expect(draft.songs[4].artist == "Ozzy & Lemmy")
        #expect(draft.missing == nil)
    }

    @Test("a pasted list: numbering, times and side headers drop out")
    func pastedList() {
        let text = """
        Side A
        1. "Perry Mason" – 5:53
        02 - I Just Want You (4:56)

        A3 Ghost Behind My Eyes 5:10
        • Thunder Underground
        """
        #expect(CDDraft.titles(fromPasted: text) == ["Perry Mason", "I Just Want You", "Ghost Behind My Eyes", "Thunder Underground"])
        var draft = CDDraft(disc: Self.ozzmosis)
        #expect(draft.applyPasted(text) == 4)
        #expect(draft.songs[0].title == "Track 1")
    }

    @Test("a ripped file has tags that the import reads back")
    func ripRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cd-rip-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("1 Audio Track.aiff")
        try Self.writeSilence(to: source, seconds: 1)

        var draft = CDDraft(disc: Self.ozzmosis)
        draft.songs = [CDDraft.Song(number: 3, title: "Ghost Behind My Eyes", artist: "",
                                    durationMilliseconds: 1000, file: source)]
        draft.album = "Ozzmosis"
        draft.albumArtist = "Ozzy Osbourne"
        draft.year = "1995"
        draft.isCompilation = true
        draft.cover = Self.tinyJPEG()

        let outcome = await CDRipper.rip(draft, as: .appleLossless, root: root)
        #expect(outcome.failed.isEmpty)
        let file = try #require(outcome.files.first)
        #expect(file.path.hasSuffix("Compilations/Ozzmosis/03 Ghost Behind My Eyes.m4a"))

        let candidate = try await AudioImport.candidate(at: file)
        #expect(candidate.draft.title == "Ghost Behind My Eyes")
        #expect(candidate.draft.album == "Ozzmosis")
        #expect(candidate.draft.albumArtist == "Ozzy Osbourne")
        #expect(candidate.draft.artist == "Ozzy Osbourne")
        #expect(candidate.draft.trackNumber == 3 && candidate.draft.totalTracks == 1)
        #expect(candidate.draft.year == 1995)
        #expect(candidate.draft.isCompilation)
        #expect(candidate.draft.kind == .appleLossless)
        #expect(candidate.artwork != nil)
        #expect(candidate.verdict.isSupported)
    }

    static func writeSilence(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44_100, channels: 2, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatInt16, interleaved: true)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        try file.write(from: buffer)
    }

    static func tinyJPEG() -> Data {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

/// Network responses when recognizing a disc: the size limit and redirects
/// (security audit 0.1.3). The server is substituted with URLProtocol, without going to the network.
@Suite("MusicBrainz: response limits", .serialized)
struct MusicBrainzFetchTests {

    final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var declaresLength = true
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var headers = ["Content-Type": "application/json"]
            if Self.declaresLength { headers["Content-Length"] = String(Self.body.count) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func fetch(_ body: Data, declaresLength: Bool, limit: Int) async throws -> Data {
        StubProtocol.body = body
        StubProtocol.declaresLength = declaresLength
        let request = URLRequest(url: URL(string: "https://musicbrainz.org/ws/2/discid/x")!)
        return try await MusicBrainz.fetch(request, session: session(), limit: limit).0
    }

    @Test("a response within the limit arrives whole")
    func withinLimit() async throws {
        #expect(try await fetch(Data(repeating: 7, count: 1000), declaresLength: true, limit: 1000).count == 1000)
    }

    @Test("a too large response is cut off: after the header and midway, when the server gives no length")
    func overLimit() async throws {
        let body = Data(repeating: 7, count: 1001)
        await #expect(throws: MusicBrainz.LookupError.self) { try await fetch(body, declaresLength: true, limit: 1000) }
        await #expect(throws: MusicBrainz.LookupError.self) { try await fetch(body, declaresLength: false, limit: 1000) }
    }

    @Test("redirects only over HTTPS to MusicBrainz and the Cover Art Archive")
    func redirects() {
        let allows = { MusicBrainz.RedirectPolicy.allows(URL(string: $0)) }
        #expect(allows("https://musicbrainz.org/ws/2/release/x"))
        #expect(allows("https://coverartarchive.org/release/x/front-500"))
        #expect(allows("https://ia800505.us.archive.org/12/items/mbid-x/mbid-x-1_thumb500.jpg"))
        #expect(!allows("http://ia800505.us.archive.org/x.jpg"))
        #expect(!allows("https://evilarchive.org/x.jpg"))
        #expect(!allows("https://archive.org.example.com/x.jpg"))
        #expect(!allows("file:///etc/passwd"))
    }
}
