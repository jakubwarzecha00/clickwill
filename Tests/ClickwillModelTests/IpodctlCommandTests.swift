import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel
@testable import ipodctl

/// `ipodctl` commands called as from the command line, on the fake iPod from the write
/// tests (`WriteTests.rig`), with backups in a temporary folder.
@Suite("ipodctl")
@MainActor
struct IpodctlCommandTests {

    private func call(_ arguments: String..., on rig: WriteTests.Rig) -> Invocation {
        Invocation(arguments: arguments + ["--volume", rig.paths.mountPoint.path], environment: rig.environment)
    }

    @Test("arguments: flag values and --volume are not files")
    func positionalArguments() {
        let call = Invocation(arguments: ["add", "a.mp3", "--album", "B", "--apply", "c.mp3", "--volume", "/Volumes/iPod"])
        #expect(call.positional(valueFlags: ["--album"]) == ["a.mp3", "c.mp3"])
        #expect(call.value(for: "--album") == "B")
        #expect(call.has("--apply"))
        #expect(Invocation(arguments: ["copy", "--album", "A", "--album", "B"]).values(for: "--album") == ["A", "B"])
        #expect(Invocation(arguments: ["tracks", "--album"]).value(for: "--album") == nil)
    }

    @Test("remove: a record pointing to a folder in Music disappears from the database, the folder and the files stay")
    func removeKeepsFolder() async throws {
        let rig = try await WriteTests.rig(WriteTests.Fixture(pointsAtFolder: 10)); defer { rig.cleanUp() }
        let filesBefore = try rig.musicFiles()

        try await RemoveCommand.run(call("remove", "--id", "10", "--apply", on: rig))

        #expect(!(try rig.onDisk().tracks.contains { $0.uniqueID == 10 }))
        #expect(try rig.musicFiles() == filesBefore)
        #expect(try rig.backups.list(deviceGUID: WriteTests.guid).count == 1, "a backup in the invocation environment")
    }

    @Test("add: the iPod path from --volume does not end up among the files to add")
    func addIgnoresVolumePath() async throws {
        // A WAV track in the database - the record template for the added WAV.
        let rig = try await WriteTests.rig(WriteTests.Fixture(hiRes: 14)); defer { rig.cleanUp() }
        // An audio file in Music without an entry - if the iPod path were a source, it would reach the database.
        try WriteTests.wave(bitDepth: 16, sampleRate: 44_100).write(to: rig.paths.musicDirectory.appendingPathComponent("F00/STRAY.wav"))
        let source = rig.root.appendingPathComponent("Only Shallow.wav")
        try WriteTests.wave(bitDepth: 16, sampleRate: 44_100).write(to: source)

        try await AddCommand.run(call("add", source.path, "--album", "Loveless", "--artist", "My Bloody Valentine", "--apply", on: rig))

        let tracks = try rig.onDisk().tracks
        #expect(tracks.count == 8, "\(tracks.map(\.title))")
        #expect(tracks.contains { $0.album == "Loveless" })
    }

    @Test("command errors are thrown, not ending the process")
    func errorsAreThrown() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        await #expect { try await SetFieldCommand.run(call("set-field", "--album", "The Bends", "--field", "nope", "--value", "x", on: rig)) }
            throws: { "\($0)".contains("unknown field") }
        await #expect { try await RemoveCommand.run(call("remove", on: rig)) }
            throws: { $0 is CommandError }
    }
}
