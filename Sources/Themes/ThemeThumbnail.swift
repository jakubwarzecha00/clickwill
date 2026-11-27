import SwiftUI
import ClickwillShared

/// A small Clickwill window in a palette: the sidebar, the toolbar, and the Cover Flow scene
/// with covers and the slider. Drawn from plain shapes, so the themes module needs no screen
/// module. Every size is a share of the width, so one drawing serves a tile in Settings and
/// the large preview in the editor.
struct ThemeThumbnail: View {
    let palette: ThemePalette

    /// The library window's default size.
    static let aspectRatio: CGFloat = 1300.0 / 820.0

    /// Covers stand for album art, so they keep their own colors in every theme.
    private static let covers: [Color] = [
        Color(red: 0.88, green: 0.48, blue: 0.37), Color(red: 0.24, green: 0.25, blue: 0.36),
        Color(red: 0.51, green: 0.70, blue: 0.60), Color(red: 0.95, green: 0.80, blue: 0.56),
        Color(red: 0.37, green: 0.38, blue: 0.81), Color(red: 0.28, green: 0.75, blue: 0.89),
        Color(red: 0.95, green: 0.36, blue: 0.71),
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let unit = size.width / 100
            let sidebarWidth = size.width * 0.22
            let toolbarHeight = size.height * 0.1
            HStack(spacing: 0) {
                sidebar(unit: unit)
                    .frame(width: sidebarWidth, height: size.height)
                    .background(palette.bg)
                Rectangle().fill(palette.sep).frame(width: max(0.5, unit * 0.1))
                VStack(spacing: 0) {
                    toolbar(unit: unit)
                        .frame(height: toolbarHeight)
                    scene(size: CGSize(width: size.width - sidebarWidth, height: size.height - toolbarHeight), unit: unit)
                }
            }
            .background(palette.stage)
            .clipShape(RoundedRectangle(cornerRadius: unit * 3.5))
            .overlay(RoundedRectangle(cornerRadius: unit * 3.5).strokeBorder(.separator, lineWidth: 0.5))
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
    }

    private func sidebar(unit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: unit * 1.6) {
            HStack(spacing: unit * 0.9) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { light in
                    Circle().fill(light).frame(width: unit * 1.6, height: unit * 1.6)
                }
            }
            .padding(.bottom, unit * 2)
            ForEach(Array([10.0, 8.0, 9.0, 7.0, 11.0].enumerated()), id: \.offset) { index, length in
                HStack(spacing: unit * 1.2) {
                    RoundedRectangle(cornerRadius: unit * 0.4).fill(palette.accent)
                        .frame(width: unit * 1.6, height: unit * 1.6)
                    Capsule().fill(palette.fg.opacity(0.75)).frame(width: unit * length, height: unit * 1)
                }
                .padding(.horizontal, unit * 1.2)
                .frame(maxWidth: .infinity, minHeight: unit * 3.4, alignment: .leading)
                .background(index == 0 ? palette.sel : .clear, in: RoundedRectangle(cornerRadius: unit * 0.8))
            }
            Spacer(minLength: 0)
        }
        .padding(unit * 2)
    }

    private func toolbar(unit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: unit * 0.8) {
            Capsule().fill(palette.fg).frame(width: unit * 12, height: unit * 1.2)
            Capsule().fill(palette.f3).frame(width: unit * 8, height: unit * 0.8)
        }
        .padding(.leading, unit * 2.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func scene(size: CGSize, unit: CGFloat) -> some View {
        let horizon = size.height * 0.64
        let side = size.height * 0.4
        return ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [palette.flowTop, palette.flowBottom], startPoint: .top, endPoint: .bottom)
                    .frame(height: horizon)
                LinearGradient(colors: [palette.floorTop, palette.floorBottom], startPoint: .top, endPoint: .bottom)
            }
            VStack(spacing: unit * 0.8) {
                Capsule().fill(palette.sceneText).frame(width: side * 0.55, height: unit * 1.2)
                Capsule().fill(palette.sceneTextSoft).frame(width: side * 0.35, height: unit * 0.9)
            }
            .position(x: size.width / 2, y: horizon - side - unit * 4.5)
            covers(side: side)
                .position(x: size.width / 2, y: horizon - side / 2)
            slider(unit: unit)
                .frame(width: size.width * 0.72)
                .position(x: size.width / 2, y: size.height - unit * 3.5)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func covers(side: CGFloat) -> some View {
        HStack(spacing: -side * 0.48) {
            ForEach(0..<7, id: \.self) { index in
                let offset = index - 3
                Rectangle()
                    .fill(Self.covers[index])
                    .overlay(Rectangle().fill(palette.sceneShade.opacity(offset == 0 ? 0 : 0.35)))
                    .frame(width: side, height: side)
                    .rotation3DEffect(.degrees(offset == 0 ? 0 : (offset < 0 ? 62 : -62)), axis: (x: 0, y: 1, z: 0),
                                      perspective: 0.6)
                    .shadow(color: palette.sceneShadow.opacity(0.45), radius: side * 0.06, y: side * 0.04)
                    .zIndex(Double(3 - abs(offset)))
                    .padding(.horizontal, offset == 0 ? side * 0.4 : 0)
            }
        }
    }

    private func slider(unit: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.sceneText.opacity(0.16)).frame(height: unit * 0.6)
                Capsule().fill(palette.accent.opacity(0.42)).frame(width: width * 0.45, height: unit * 0.6)
                Capsule().fill(palette.sliderKnob).frame(width: unit * 1.8, height: unit * 2.2)
                    .shadow(color: palette.sceneShadow.opacity(0.45), radius: unit * 0.3, y: unit * 0.2)
                    .offset(x: width * 0.45 - unit * 0.9)
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: unit * 2.4)
    }
}

/// The System tile: the dark window on the left half, the light one on the right.
struct SystemThumbnail: View {
    var body: some View {
        ThemeThumbnail(palette: .dark)
            .overlay {
                ThemeThumbnail(palette: .light)
                    .mask {
                        HStack(spacing: 0) {
                            Color.clear
                            Color.black
                        }
                    }
            }
    }
}
