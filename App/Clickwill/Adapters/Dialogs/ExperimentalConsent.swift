import AppKit

/// The permission for experimental writing on one iPod. Says what the permission covers
/// and what undoes it; Cancel is the default button.
enum ExperimentalConsent {

    /// The warning before Developer Mode, which lifts more than a permission for one iPod does.
    @MainActor
    static func askDeveloperMode() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Turn on Developer Mode?"
        alert.informativeText = """
            Developer Mode is for developers measuring an iPod model that is not confirmed yet. \
            It allows writing to any iPod with an unsigned database, and to disk images, without \
            the list of confirmed models, the USB confirmation or the list of measured artwork formats.

            A write the iPod does not understand can leave its library empty or broken until a backup \
            is restored. Kept: the signature check, identity conflicts and the backup before every write.
            Developer Mode ends when Clickwill quits.
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Turn On")
        return alert.runModal() == .alertSecondButtonReturn
    }

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
