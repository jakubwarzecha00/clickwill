import Foundation
import ITDBKit

/// `rewrite` - rewriting the database to the iPod unchanged (a hardware test). It goes
/// through the transaction like every write, so the repairs during the write run too -
/// a healthy database comes out byte for byte the same.
enum RewriteCommand {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        guard device.supportsWriting else { throw CommandError(device.readOnlyReason?.description ?? "writing blocked") }
        let onDevice = try DeviceLibrary(reading: device, for: call)
        let outcome = try await onDevice.write(onDevice.library, note: "hardware test: rewrite without changes")
        announce(outcome)
        report("\nDatabase rewritten", [
            ("signature", outcome.result.signature),
            ("change from the previous one", outcome.result.identicalToPrevious ? "none, byte for byte" : "YES"),
        ])
        print("\n  Disconnect the iPod and check that it starts and sees the library.")
    }
}
