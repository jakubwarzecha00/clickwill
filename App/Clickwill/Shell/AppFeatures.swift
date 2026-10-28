/// Features turned off in the release, but still being developed.
enum AppFeatures {
    /// Reorder Albums is turned off in the release. On an iPod
    /// Classic, reordering changes the album order in the Artists and Albums menus,
    /// but not in Cover Flow, which the iPod lays out itself - and the screen promised Cover Flow.
    /// It comes back with a new scope (the menu order). `--screen reorder` still works
    /// for working on it.
    static let reorderAlbums = false
}
