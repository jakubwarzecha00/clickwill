import SwiftUI
import UniformTypeIdentifiers

/// Artwork with replacement: hover shows a button, the right mouse button gives a menu,
/// a dropped image file replaces it right away.
struct CoverEditor: View {
    let size: CGFloat
    let corner: CGFloat
    let image: CGImage?
    let choose: () -> Void
    let drop: (URL) -> Void
    @State private var hovering = false
    @State private var targeted = false
    /// Hover faked in a demo recording (`--demo`), without moving the cursor.
    @Environment(\.demoHover) private var demoHover

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack { Theme.card; Image(systemName: "music.note").font(.system(size: size / 6, weight: .light)).foregroundStyle(Theme.f3) }
            }
            if hovering || targeted || demoHover == "cover" {
                Color.black.opacity(0.35)
                Button(action: choose) {
                    // On the small artwork in the panel the full label got truncated ("Change Cov…").
                    Label(targeted ? (size < 160 ? "Drop Here" : "Drop to use as cover")
                                   : (size < 160 ? "Change…" : "Change Cover…"), systemImage: "photo")
                        .font(.theme(.callout, weight: .medium)).glassChip(selected: true)
                }
                .chipButton(selected: true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(RoundedRectangle(cornerRadius: corner).stroke(targeted ? Theme.accent : .clear, lineWidth: 2))
        .onHover { hovering = $0 }
        .contextMenu { Button("Change Cover…", action: choose) }
        // For VoiceOver (and demo recordings): the artwork as a single button.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Album Cover")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { choose() }
        .accessibilityAction(named: "Change Cover…") { choose() }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            Task { if let url = await NSItemProvider.fileURLs(from: [provider]).first { drop(url) } }
            return true
        }
    }
}
