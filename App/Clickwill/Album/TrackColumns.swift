import SwiftUI

/// Track list columns - shared by the header and the rows, in an album and in an album
/// waiting to be written. The header and the row are computed from the same numbers,
/// otherwise the numbers drift away from their headers.
enum TrackColumns {
    /// The spacing between columns.
    static let spacing: CGFloat = 12
    /// The content inset from the row edge (and the header's).
    static let inset: CGFloat = 10
    static let number: CGFloat = 34
    static let plays: CGFloat = 78
    static let time: CGFloat = 62
    /// The row menu (three dots) or the remove button.
    static let menu: CGFloat = 22
    /// The content inset from the top and bottom of the row.
    static let rowPadding: CGFloat = 10
    /// The line under a row starts under the title, not under the number.
    static let dividerLeading: CGFloat = inset + number + spacing
}

extension View {
    /// Track rows separated by a thin line instead of separate pills
    /// (modeled on an album's track list in Music). Under
    /// a highlighted row there is no line - the highlight separates it by itself.
    func trackRowDivider(hidden: Bool = false) -> some View {
        overlay(alignment: .bottom) {
            Theme.sep.frame(height: 0.5)
                .padding(.leading, TrackColumns.dividerLeading)
                .opacity(hidden ? 0 : 1)
        }
    }
}
