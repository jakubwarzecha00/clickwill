import SwiftUI
import AppKit
import ClickwillModel

/// Confirmation for deleting a whole album.
///
/// Deleting is the only thing a backup does **not** undo: a snapshot
/// holds the database and artwork, not the audio files. That is why the dialog says so plainly and offers
/// a middle way - save copies on the Mac, and only then delete.
enum DeleteAlbumConfirmation {

    enum Choice {
        /// Delete, and save copies of the files in this folder.
        case deleteKeepingCopies(URL)
        case delete
        case cancelled
    }

    @MainActor
    static func ask(album: String, artist: String, trackCount: Int, fileCount: Int,
                    folder: RememberedFolder = .deletedCopies) -> Choice {
        let alert = NSAlert()
        alert.messageText = "Delete “\(album)”?"

        var text = "\(trackCount) \(trackCount == 1 ? "song" : "songs") by \(artist) will be removed from the iPod's library"
        if fileCount > 0 {
            text += ", and \(fileCount) \(fileCount == 1 ? "file" : "files") will be erased from the iPod itself."
            text += "\n\nClickwill backs up the database before every write, so the library can be restored, "
            text += "but a backup doesn't hold your music. Once the \(fileCount == 1 ? "file is" : "files are") erased, "
            text += "\(fileCount == 1 ? "it is" : "they are") gone from the iPod for good."
        } else {
            text += ". No files will be erased: these entries have no file on the iPod."
        }
        if let last = folder.url { text += "\n\nLast used for copies: \(last.path)" }
        alert.informativeText = text
        alert.alertStyle = .warning

        if fileCount > 0 { alert.addButton(withTitle: "Save Copies and Delete…") }
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")

        let response = alert.runModal()
        // Without files to delete, the first button is "Cancel", so the button
        // numbers are counted from what we actually added.
        guard fileCount > 0 else {
            return response == .alertSecondButtonReturn ? .delete : .cancelled
        }
        switch response {
        case .alertFirstButtonReturn:
            guard let url = FilePanels.chooseFolder(
                message: "Where should the copies of these songs be kept?", prompt: "Keep Copies Here",
                startingIn: folder.startingPoint, canCreate: true) else { return .cancelled }
            folder.url = url
            return .deleteKeepingCopies(url)
        case .alertThirdButtonReturn:
            return .delete
        default:
            return .cancelled
        }
    }
}
