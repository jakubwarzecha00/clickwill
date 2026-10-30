import SwiftUI
import AppKit

extension View {
    /// On macOS 14-25 the `.roundedBorder` style draws a single-line system field
    /// and ignores `axis: .vertical` and the line reserve - the message had one
    /// line (checked on macOS 14). There, a `.plain` field with its own frame and field background.
    @ViewBuilder func multilineFieldStyle() -> some View {
        if #available(macOS 26, *) {
            textFieldStyle(.roundedBorder)
        } else {
            textFieldStyle(.plain)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }
}
