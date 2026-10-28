import Foundation

/// The last chosen folder, remembered in the preferences. It serves only as
/// a suggestion in the choose panel and in the dialog text - never as a silent
/// default.
struct RememberedFolder {
    let key: String

    var url: URL? {
        get { UserDefaults.standard.string(forKey: key).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        nonmutating set { UserDefaults.standard.set(newValue?.path, forKey: key) }
    }

    /// Originals set aside before a conversion.
    static var originals: RememberedFolder { RememberedFolder(key: "clickwill.originals.lastDirectory") }
    /// Copies of files saved before deleting an album.
    static var deletedCopies: RememberedFolder { RememberedFolder(key: "clickwill.deletedCopies.lastDirectory") }

    /// The panel's starting point: the last choice or the Music folder.
    var startingPoint: URL? {
        url ?? FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
    }
}
