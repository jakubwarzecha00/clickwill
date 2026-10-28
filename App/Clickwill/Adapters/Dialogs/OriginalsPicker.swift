import SwiftUI
import AppKit
import ClickwillModel

/// Choosing a place for the originals before a conversion. A conversion to 16 bits cannot
/// be undone, so we ask **every time** - the last folder serves only
/// as a suggestion in the panel, never as a silent default.
enum OriginalsPicker {

    enum Choice {
        case keep(URL)
        case discard
        case cancelled
    }

    /// Asks for a place for the originals. `title` describes what the conversion concerns.
    @MainActor
    static func ask(for title: String, fileCount: Int, sizeHint: String?, folder: RememberedFolder = .originals) -> Choice {
        let alert = NSAlert()
        alert.messageText = "Keep the original \(fileCount == 1 ? "file" : "files")?"
        var text = "\(title) will be converted to a format the iPod can play. "
            + "Converting to 16-bit can't be undone, so the \(fileCount == 1 ? "original file" : "original files") should be kept somewhere on this Mac."
        if let sizeHint { text += "\n\nOriginals: about \(sizeHint)." }
        if let last = folder.url { text += "\nLast used: \(last.path)" }
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Convert Without a Copy")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard let url = FilePanels.chooseFolder(
                message: "Where should the original files be kept?", prompt: "Keep Originals Here",
                startingIn: folder.startingPoint, canCreate: true) else { return .cancelled }
            folder.url = url
            return .keep(url)

        case .alertThirdButtonReturn:
            // The second barrier: having no copy is a decision that cannot be undone.
            let confirm = NSAlert()
            confirm.messageText = "Convert without keeping the originals?"
            confirm.informativeText = "The higher-resolution \(fileCount == 1 ? "file" : "files") will be deleted from the iPod after the write. This can't be undone."
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Cancel")
            confirm.addButton(withTitle: "Delete Originals")
            return confirm.runModal() == .alertSecondButtonReturn ? .discard : .cancelled

        default:
            return .cancelled
        }
    }
}
