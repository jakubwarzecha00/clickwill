import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// A counter and a stash for the fakes - the `Discovery` and `LastUsed` closures are @Sendable.
private final class Probe: @unchecked Sendable {
    var devicesAsked = 0
    var mounts: [URL] = []
    var devices: [IPodDevice] = []
    var lastUsed: String?
}

@Suite("Connected iPods")
@MainActor
struct DeviceConnectionsTests {

    private func connections(_ probe: Probe) -> DeviceConnections {
        DeviceConnections(
            discovery: .init(mountPoints: { probe.mounts },
                             devices: { probe.devicesAsked += 1; return probe.devices }),
            lastUsed: .init(load: { probe.lastUsed }, save: { probe.lastUsed = $0 }))
    }

    @Test("the list refreshes only when the volumes change or on request")
    func refreshOnlyOnChange() async throws {
        let a = try await WriteTests.rig(); defer { a.cleanUp() }
        let device = try #require(a.model.device)
        let probe = Probe()
        probe.mounts = [device.volume.mountPoint]
        probe.devices = [device]
        let connections = connections(probe)

        connections.refresh(force: false, loaded: nil, loadedName: nil)
        connections.refresh(force: false, loaded: nil, loadedName: nil)
        #expect(probe.devicesAsked == 1, "the same set of volumes - without asking the iPod over USB")
        #expect(connections.choices.map(\.id) == [device.identity])

        connections.refresh(force: true, loaded: nil, loadedName: nil)
        #expect(probe.devicesAsked == 2)

        probe.mounts = []
        probe.devices = []
        connections.refresh(force: false, loaded: nil, loadedName: nil)
        #expect(connections.choices.isEmpty)
    }

    @Test("a loaded iPod has the name from its library; a backup from disk does not go onto the list")
    func loadedNameAndSnapshot() async throws {
        let a = try await WriteTests.rig(); defer { a.cleanUp() }
        let device = try #require(a.model.device)
        let probe = Probe()
        probe.mounts = [device.volume.mountPoint]
        probe.devices = [device]
        let connections = connections(probe)

        connections.refresh(force: true, loaded: .device(device), loadedName: "iPod (Test)")
        #expect(connections.choices.first?.name == "iPod (Test)")
        #expect(connections.choice(for: .device(device), name: nil)?.name == "iPod (Test)")

        connections.refresh(force: true, loaded: .snapshot(a.root), loadedName: nil)
        #expect(connections.choices.isEmpty)
    }

    @Test("without a memory or with an unknown iPod in it - the first connected; loading remembers it")
    func preferredIsLastUsed() async throws {
        let a = try await WriteTests.rig(); defer { a.cleanUp() }
        let b = try await WriteTests.rig(); defer { b.cleanUp() }
        let first = try #require(a.model.device), second = try #require(b.model.device)
        let probe = Probe()
        probe.devices = [first, second]
        let connections = connections(probe)

        #expect(connections.preferredSource() == .device(first), "without a memory - the first")
        connections.remember(second)
        #expect(probe.lastUsed == second.identity)

        probe.lastUsed = "000A2700FFFFFFFF"
        #expect(connections.preferredSource() == .device(first), "an unknown iPod in the memory - the first connected")
    }

    @Test("with two different iPods the last used one loads, in any order of connecting")
    func lastUsedWins() async throws {
        let a = try await WriteTests.rig(); defer { a.cleanUp() }
        let b = try await WriteTests.rig(WriteTests.Fixture(guid: "000A2700AABBCCDD")); defer { b.cleanUp() }
        let first = try #require(a.model.device), second = try #require(b.model.device)
        #expect(first.identity != second.identity)
        let probe = Probe()
        probe.lastUsed = second.identity
        let connections = connections(probe)

        probe.devices = [first, second]
        #expect(connections.preferredSource() == .device(second))
        probe.devices = [second, first]
        #expect(connections.preferredSource() == .device(second))
    }

    @Test("the demo list replaces real devices")
    func demoChoices() {
        let probe = Probe()
        let connections = connections(probe)
        connections.demoChoices = [try! #require(IPodChoice(demoArgument: "/tmp/backup|iPod (Demo)|iPod classic|160|20"))]
        connections.refresh(force: true, loaded: nil, loadedName: nil)
        #expect(probe.devicesAsked == 0)
        #expect(connections.choices.map(\.name) == ["iPod (Demo)"])
    }

    @Test("the model remembers the loaded iPod through the injected memory")
    func modelRemembersLoadedDevice() async throws {
        let a = try await WriteTests.rig(); defer { a.cleanUp() }
        let probe = Probe()
        let model = LibraryModel(environment: a.environment, connections: connections(probe))
        await model.load(try #require(a.model.source))
        #expect(probe.lastUsed == WriteTests.guid)
    }
}
