import Foundation
import Testing
@testable import ClickwillModel
import ITDBKit

@Suite("Choosing an iPod")
struct IPodChoiceTests {

    @Test("--demo-ipod: backup, name, model, capacity and used space")
    func demoArgument() throws {
        let choice = try #require(IPodChoice(demoArgument: "/tmp/backup|Car iPod|iPod classic|80|31.2"))
        #expect(choice.name == "Car iPod")
        #expect(choice.modelName == "iPod classic")
        #expect(choice.totalCapacity == 80_000_000_000)
        #expect(choice.availableCapacity == 48_800_000_000)
        #expect(choice.source == .snapshot(URL(fileURLWithPath: "/tmp/backup")))
        #expect(choice.readOnlyReason == nil)
    }

    @Test("--demo-ipod with a policy: the experimental badge for screenshots")
    func demoArgumentPolicy() throws {
        let choice = try #require(IPodChoice(demoArgument: "/tmp/backup|Val's iPod|iPod (5th generation)|30|12|video:black:experimental"))
        #expect(choice.outsideConfirmedModels && choice.writePolicy == .experimental)
    }

    @Test("--demo-ipod with a missing field or number is not an iPod")
    func demoArgumentRejected() {
        #expect(IPodChoice(demoArgument: "/tmp/backup|Car iPod|iPod classic|80") == nil)
        #expect(IPodChoice(demoArgument: "/tmp/backup|Car iPod|iPod classic|eighty|31") == nil)
    }

    @Test("without connected iPods there is nothing to choose, also with a remembered one")
    func preferredWithoutDevices() {
        #expect(DeviceConnections.preferred(among: [], lastUsed: "000A27001234ABCD") == nil)
    }
}

@Suite("The iPod name from the database")
struct DeviceNameTests {

    @Test("the quick name read gives the same as the full parser")
    func quickNameMatchesFullParse() throws {
        let data = SyntheticLibrary.database()
        let full = try ITunesDBParser.parse(data).deviceName
        #expect(full != nil)
        #expect(try ITunesDBParser.deviceName(in: data) == full)
    }

    @Test("not an iPod database - an error, not a guess")
    func notADatabase() {
        #expect(throws: (any Error).self) { try ITunesDBParser.deviceName(in: Data("hello".utf8)) }
    }
}

@Suite("The iPod name on screen and in the report")
struct DeviceNameDisplayTests {

    @Test("the name from the database, and without it (or when empty) the volume name")
    func displayNameFallback() {
        #expect(IPodChoice.displayName("iPod (Anna)", volume: "iPod") == "iPod (Anna)")
        #expect(IPodChoice.displayName(nil, volume: "iPod") == "iPod")
        #expect(IPodChoice.displayName("  ", volume: "iPod 1") == "iPod 1")
    }

    @Test("the name given to the iPod does not go into the diagnostic report")
    func reportRedactsGivenName() {
        let text = DiagnosticReport.redacted("write refused on iPod (Anna), iPod classic", names: ["iPod", "iPod (Anna)"])
        #expect(text == "write refused on <iPod name>, iPod classic")
    }
}

@Suite("Overview: albums with artwork")
@MainActor
struct AlbumsWithCoverTests {

    @Test("without ArtworkDB no album has artwork - Overview used to count all Cover Flow cards")
    func noArtworkNoCovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("covers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itunes = root.appendingPathComponent("files/iTunes", isDirectory: true)
        try FileManager.default.createDirectory(at: itunes, withIntermediateDirectories: true)
        try SyntheticLibrary.database().write(to: itunes.appendingPathComponent("iTunesDB"))
        let model = LibraryModel(); await model.load(.snapshot(root))
        #expect(!model.albums.isEmpty)
        #expect(model.albumsWithCover == 0)
    }
}

@Suite("Chooser and write policy")
@MainActor
struct ChooserPolicyTests {
    @Test("an iPod with an experimental permission is listed as experimental, not read-only")
    func experimentalInList() throws {
        let device = try ExperimentalPermissionsTests.video()
        let connections = DeviceConnections(
            discovery: .init(mountPoints: { [device.volume.mountPoint] }, devices: { [device] }),
            lastUsed: .init(load: { nil }, save: { _ in }))
        connections.refresh(force: true, loaded: nil, loadedName: nil)
        #expect(connections.choices.first?.isReadOnly == true, "without the permission: read-only")
        #expect(connections.choices.first?.outsideConfirmedModels == false)

        connections.refresh(force: true, loaded: nil, loadedName: nil, policy: { _ in .experimental })
        let choice = try #require(connections.choices.first)
        #expect(!choice.isReadOnly)
        #expect(choice.outsideConfirmedModels)
        #expect(choice.writePolicy == .experimental)
    }
}
