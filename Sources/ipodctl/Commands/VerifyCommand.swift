import Foundation
import ITDBKit

/// `verify ID` - checking a backup's checksums.
enum VerifyCommand {
    static func run(_ call: Invocation) async throws {
        guard let id = call.positional().first else { throw CommandError("give a backup identifier") }
        let device = try openDevice(call)
        let store = try openStore(call)
        let snapshot = try store.snapshot(deviceGUID: device.identity, id: id)
        try store.verify(snapshot)
        print("Backup \(snapshot.id) is consistent - \(snapshot.files.count) files match their checksums.")
    }
}
