import Foundation
import ClickwillModel

/// A screen in the window (`WindowState.screen`).
enum Screen: Hashable {
    /// The iPod's Albums menu on a wheel (`AlbumWheelScreen`).
    case albums
    case reorder
    /// A screen of a module (`Modules.swift`).
    case module(ModulePage)
}

/// Sidebar items. An open album belongs to the tab it was
/// opened from; Reorder to Albums.
enum SidebarItem: Hashable { case albums, module(ModulePage) }
