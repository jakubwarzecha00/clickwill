import AppKit

/// The permission for experimental writing on one iPod. Says what the permission covers
/// and what undoes it; Cancel is the default button.
enum ExperimentalConsent {

    @MainActor
    static func ask(modelName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Allow experimental writing to this iPod?"
        alert.informativeText = """
            \(modelName) is not a confirmed model. A backup of the database and artwork is made \
            before every write; restoring it reverts all changes.

            Allowed: editing, adding and deleting songs. Deleted audio files are copied to this Mac first.
            Disabled: new artwork in unmeasured formats, write-time repairs of albums not changed in the write.
            The first backup is kept until deleted manually. The permission lapses after a firmware update.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Allow")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
