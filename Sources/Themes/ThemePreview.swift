import SwiftUI
import ClickwillShared

/// A small picture of a window in a palette: the scene Cover Flow stands on, a list, a field
/// and the states. Drawn here from plain shapes, so the themes module needs no screen module.
struct ThemePreview: View {
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 0) {
            scene
            list
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
        // Only this panel: the sheet and the Settings window keep their own look.
        .environment(\.appTheme, AppTheme(palette: palette))
        .environment(\.colorScheme, palette.colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the theme")
    }

    private var scene: some View {
        ZStack {
            LinearGradient(colors: [palette.flowTop, palette.flowBottom], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Color.clear.frame(height: 108)
                LinearGradient(colors: [palette.floorTop, palette.floorBottom], startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: 6) {
                Text("Album Title").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.sceneText)
                Text("Artist").font(.system(size: 10)).foregroundStyle(Theme.sceneTextSoft)
                HStack(alignment: .bottom, spacing: 8) {
                    cover(42, fade: 0.45)
                    cover(60, fade: 0)
                    cover(42, fade: 0.45)
                }
                .frame(height: 62, alignment: .bottom)
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sceneText.opacity(0.16)).frame(height: 4)
                    Capsule().fill(Theme.positionSliderTint).frame(width: 70, height: 4)
                    Capsule().fill(Theme.sliderKnob).frame(width: 10, height: 13)
                        .shadow(color: palette.sceneShadow.opacity(0.45), radius: 1.5, y: 1)
                        .offset(x: 66)
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 12)
        }
        .frame(height: 150)
    }

    private func cover(_ side: CGFloat, fade: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [palette.accent, palette.card], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Rectangle().fill(palette.sceneShade.opacity(fade)))
            .frame(width: side, height: side)
            .shadow(color: palette.sceneShadow.opacity(0.6), radius: 6, y: 4)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.f2)
                Text("Search").foregroundStyle(Theme.f3)
                Spacer()
            }
            .font(.system(size: 11))
            .padding(.horizontal, 8).frame(height: 22)
            .background(Theme.field, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.fieldBorder, lineWidth: 0.5))
            row("Song One", "Artist", selected: true)
            row("Song Two", "Artist", selected: false)
            Rectangle().fill(Theme.sep).frame(height: 1)
            HStack(spacing: 8) {
                Text("Play").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12).frame(height: 22)
                    .background(Theme.accent, in: Capsule())
                Text("Link").font(.system(size: 11)).foregroundStyle(Theme.accent)
                Spacer()
                Circle().fill(Theme.warn).frame(width: 9, height: 9)
                Circle().fill(Theme.destructive).frame(width: 9, height: 9)
                Circle().fill(Theme.ok).frame(width: 9, height: 9)
            }
        }
        .padding(10)
        .background(Theme.bg)
    }

    private func row(_ title: String, _ artist: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.fg)
                Text(artist).font(.system(size: 10)).foregroundStyle(Theme.f2)
            }
            Spacer()
            Text("3:12").font(.system(size: 10)).foregroundStyle(Theme.f3)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(selected ? Theme.sel : Theme.row, in: RoundedRectangle(cornerRadius: 5))
    }
}
