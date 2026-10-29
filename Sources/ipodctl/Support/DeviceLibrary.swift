import Foundation
import ITDBKit
import ClickwillModel

/// A library read from the iPod together with the digest of the database it came from.
///
/// Every change on the iPod goes through `write`, i.e. through the same transaction
/// as in the app window (`WriteTransaction`): the device lock, the database still
/// the one read, a backup, files before the database, repairs, the database write,
/// deletion only after it, and on an error a rollback of what reached
/// the iPod. Otherwise a command would overwrite what the app, Music or a second
/// `ipodctl` wrote in the meantime, or delete a file without the checks.
struct DeviceLibrary {
    let device: IPodDevice
    let library: ITLibrary
    /// The database digest from the moment of reading (`IPodDevice.digest(of:)`).
    let digest: String
    /// The command invocation: the write environment and `--allow-music`.
    let call: Invocation

    /// The library and the digest from the same bytes - two separate reads could
    /// hit two different databases.
    init(reading device: IPodDevice, for call: Invocation) throws {
        let data = try device.readDatabase()
        self.device = device
        self.library = try ITunesDBParser.parse(data)
        self.digest = IPodDevice.digest(of: data)
        self.call = call
    }

    /// Writes `updated` and carries out the tasks from `changes`. An error ends the command:
    /// the transaction has already rolled back what it did, and the database was not written.
    /// - Parameter jumpTable: the jump bar in the order intent saved after the write.
    func write(_ updated: ITLibrary, changes: ChangeSet = ChangeSet(), note: String,
               jumpTable: JumpTablePolicy = .derived) async throws -> WriteOutcome {
        var transaction = WriteTransaction(library: updated, changes: changes, device: device,
                                           capabilities: IPodCapabilities.resolve(for: device),
                                           environment: call.environment, note: note)
        transaction.expectedSourceDigest = digest
        transaction.allowWhileMusicRunning = call.has("--allow-music")
        transaction.orderIntentJumpTable = jumpTable
        transaction.progress = { print("  \($0)") }
        do { return try await transaction.run().outcome } catch { throw CommandError("\(error) - the database was not written") }
    }
}
