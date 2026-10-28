import Foundation

/// The product name in one place. It also determines the folder for backups
/// and the remembered order, so we never write it anywhere else.
public enum ProductInfo {
    public static let name = "Clickwill"

    /// Names the app went by earlier. The data folder is moved
    /// from the first one found - otherwise a rename would leave the user
    /// without their backups, and those are the only thing standing
    /// between them and an irreversible mistake on the device.
    ///
    /// "Clickwheel" was dropped, because Click Wheel is an Apple trademark.
    public static let previousNames = ["Clickwheel"]

    /// The app's data folder, moved from the old name if needed.
    public static func supportDirectory(
        named productName: String = name, previous: [String] = previousNames
    ) throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        let current = support.appendingPathComponent(productName, isDirectory: true)
        guard !manager.fileExists(atPath: current.path) else { return current }

        for old in previous {
            let candidate = support.appendingPathComponent(old, isDirectory: true)
            guard manager.fileExists(atPath: candidate.path) else { continue }
            // Same volume, so the move is cheap and keeps the
            // hard links that incremental backups rely on.
            do { try manager.moveItem(at: candidate, to: current); return current }
            catch { continue }
        }
        return current
    }
}
