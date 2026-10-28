import Foundation
import ITDBKit

/// `hash58` - database signature verification (gate T1.2).
enum Hash58Command {
    static func run(_ call: Invocation) async throws {
        let device = try openDevice(call)
        let verification = try device.verifySignature()
        guard let result = verification else {
            report("Signature gate", [
                ("format", device.format.name),
                ("conclusion", "this database is not signed - there is nothing to verify"),
            ])
            return
        }
        report("hash58 gate", [
            ("GUID", device.fireWireID?.hex ?? "-"),
            ("in the database", result.stored.hexString),
            ("computed", result.computed.hexString),
        ])
        guard result.matches else {
            throw CommandError("the signatures differ - writing to this device is not allowed")
        }
        print("\n  MATCH - we can sign our own databases for this device.")
    }
}
