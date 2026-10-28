import AppKit
import Foundation

/// Ejecting the iPod from within the app.
///
/// The reason is a hard one, not cosmetic: the iPod Classic reads the database on eject,
/// not continuously. A cable pulled without ejecting leaves the device
/// showing the state from before the write - and it looks exactly as if the write
/// had failed. Since the app writes that database, it must also give a way for the iPod
/// to read it.
enum DeviceEject {

    enum Outcome {
        case ejected
        case cancelled
        case failed(String)
    }

    /// Asks when there is something to ask about, and ejects. Unsaved changes are the only
    /// reason worth stopping here for - they are lost, because they live
    /// only in the app's memory.
    @MainActor
    static func run(mountPoint: URL, pendingChanges: Int) -> Outcome {
        if pendingChanges > 0 {
            let alert = NSAlert()
            alert.messageText = "Eject with \(pendingChanges) \(pendingChanges == 1 ? "change" : "changes") unwritten?"
            alert.informativeText = """
                \(pendingChanges == 1 ? "One change is" : "These changes are") only in this app. \
                Nothing has been written to the iPod yet. Ejecting now throws \
                \(pendingChanges == 1 ? "it" : "them") away.

                Write first if you want to keep \(pendingChanges == 1 ? "it" : "them").
                """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Eject Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: mountPoint)
            return .ejected
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The message after a failed eject. The system usually says only that the volume
    /// is busy - not by what, and that is the only thing the user can
    /// fix.
    @MainActor
    static func report(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = "The iPod couldn't be ejected"
        alert.informativeText = """
            \(reason)

            Something on this Mac is still using the volume. Apple Music is the \
            usual culprit; a Finder window open on the iPod can also hold it.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
