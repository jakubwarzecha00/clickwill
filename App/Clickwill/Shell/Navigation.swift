import Foundation
import ClickwillModel

/// A screen in the window (`WindowState.screen`).
enum Screen: Hashable {
    case coverFlow
    /// The iPod's Albums menu on a wheel (`AlbumWheelScreen`).
    case albums
    case album(AlbumCard)
    case reorder
    case songs
    case artists
    case artist(String)
    case overview
    case backups
    /// A disc in the drive, by the volume URL.
    case audioCD(URL)
}

/// Sidebar items. An open album belongs to the tab it was
/// opened from; Reorder to Albums.
enum SidebarItem: Hashable { case coverFlow, albums, songs, artists, overview, backups, disc(URL) }
