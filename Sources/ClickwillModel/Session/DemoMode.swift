import Foundation
import ITDBKit

/// The app's demo mode: website recordings, screenshots and ads.
///
/// Passed in from outside when the model is created (`LibraryModel(demo:)`) and
/// fixed from then on. The model does not read launch flags - the app layer does that.
public struct DemoMode: Sendable {
    /// Edits live only in memory: writing to the iPod, on-demand backups
    /// and restoring backups are blocked.
    public var blocksWrites = false
    /// A backup from disk shown as a connected iPod with this description in the sidebar,
    /// e.g. "iPod classic · 160 GB". The interface behaves as with a
    /// connected, recognized iPod classic, and writing still refuses.
    /// Works only together with `blocksWrites`.
    public var deviceDetail: String?
    /// iPods for the chooser, instead of real devices.
    public var choices: [IPodChoice] = []

    public init(blocksWrites: Bool = false, deviceDetail: String? = nil, choices: [IPodChoice] = []) {
        self.blocksWrites = blocksWrites
        self.deviceDetail = deviceDetail
        self.choices = choices
    }

    public static let off = DemoMode()

    /// Whether we show this source as a connected iPod.
    func presentsAsDevice(_ source: LibrarySource?) -> Bool {
        guard blocksWrites, deviceDetail != nil, case .snapshot? = source else { return false }
        return true
    }
}
