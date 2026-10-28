import AppKit
import ClickwillModel

/// Confirmation for clearing the compilation flag.
///
/// The flag changes where the iPod places the album - and that cannot be shown before
/// the write, because the app predicts the Cover Flow layout instead of reading it.
/// That is why we ask instead of changing right away, and say plainly what we do not know.
enum CompilationConfirmation {

    @MainActor
    static func askToTakeOut(_ album: AlbumCard) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Take “\(album.displayTitle)” out of Compilations?"
        alert.informativeText = """
            The compilation tag will be removed from \(album.trackCount) \
            \(album.trackCount == 1 ? "song" : "songs"), so the album belongs to \
            “\(album.displayArtist)” alone.

            Keep the tag if the album really is by several artists, like a film \
            soundtrack. Remove it when the tag is simply wrong.

            The album leaves the block of compilations at the far right of Cover \
            Flow and takes its place among the rest. Its position in the Albums \
            menu does not change, and nothing reaches the iPod until you choose Write to iPod.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Take Out")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
