import SwiftUI
import AppKit
import ITDBKit
import ClickwillModel

/// The iPod drawing: our own vector illustration in the shape of the case,
/// in the color from the model catalog. No Apple photos or renders.
///
/// The shape from the generation (`IPodCatalog.Generation`), and without it - from the USB
/// family. The color only from a confirmed serial number suffix, otherwise neutral. Dimensions in fractions of the case
/// width and height, so the drawing looks the same at 18 and at 120 pt.
struct IPodGraphic: View {
    let shape: Shape
    let finish: IPodCatalog.Finish?

    /// Case shapes. Each with a layout measured on reference photos.
    enum Shape: Equatable, CaseIterable {
        case early, third, fourth, photo, video, mini
        case classic, nano1, nano2, nano3, nano4, generic

        init(generation: IPodCatalog.Generation?, usbFamily: String?) {
            switch generation {
            case .firstSecond?: self = .early
            case .third?: self = .third
            case .fourth?: self = .fourth
            case .photo?: self = .photo
            case .video?: self = .video
            case .mini?: self = .mini
            case .classic1?, .classic2?, .classic3?: self = .classic
            case .nano1?: self = .nano1
            case .nano2?: self = .nano2
            case .nano3?: self = .nano3
            case .nano4?: self = .nano4
            case .nano5?, .nano6?: self = .generic
            case nil:
                // Without a generation (e.g. a classic 160 GB without firmware) - the USB family.
                let family = usbFamily?.lowercased() ?? ""
                if family.contains("classic") { self = .classic }
                else if family.contains("nano (1st") { self = .nano1 }
                else if family.contains("nano (2nd") { self = .nano2 }
                else if family.contains("nano (3rd") { self = .nano3 }
                else if family.contains("nano (4th") { self = .nano4 }
                else { self = .generic }
            }
        }

        /// The case's width to height (dimensions from the product pages).
        var aspect: CGFloat {
            switch self {
            case .early: 61.0 / 102.0
            case .third, .fourth, .photo: 61.8 / 104.0
            case .video, .classic, .generic: 61.8 / 103.5
            case .mini: 50.8 / 91.0
            case .nano1, .nano2: 40.0 / 90.0
            case .nano3: 52.3 / 69.8
            case .nano4: 38.7 / 90.7
            }
        }

        /// A monochrome display (gray-green), not color glass.
        var monoScreen: Bool { [.early, .third, .fourth, .mini].contains(self) }
        /// White plastic with a gray wheel (4G, photo, 5G, nano 1G).
        var greyWheelOnWhite: Bool { [.fourth, .photo, .video, .nano1].contains(self) }
    }

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
            .aspectRatio(shape.aspect, contentMode: .fit)
            .accessibilityHidden(true)
    }

    /// The layout of the case front in fractions - measured on reference photos
    /// (Wikimedia Commons), not on Apple renders.
    private struct Layout {
        let corner: CGFloat        // corner radius / width
        let screen: CGRect         // fractions of width and height
        let wheel: CGFloat         // wheel diameter / width
        let wheelY: CGFloat        // wheel center / height
        let button: CGFloat        // button diameter / wheel diameter
    }

    private var layout: Layout {
        switch shape {
        case .early:
            Layout(corner: 0.10, screen: CGRect(x: 0.16, y: 0.07, width: 0.68, height: 0.32), wheel: 0.74, wheelY: 0.71, button: 0.28)
        case .third:
            Layout(corner: 0.15, screen: CGRect(x: 0.15, y: 0.06, width: 0.72, height: 0.35), wheel: 0.72, wheelY: 0.75, button: 0.27)
        case .fourth, .photo:
            Layout(corner: 0.12, screen: CGRect(x: 0.15, y: 0.065, width: 0.70, height: 0.33), wheel: 0.64, wheelY: 0.72, button: 0.33)
        case .video:
            Layout(corner: 0.08, screen: CGRect(x: 0.10, y: 0.055, width: 0.80, height: 0.40), wheel: 0.55, wheelY: 0.73, button: 0.36)
        case .mini:
            Layout(corner: 0.06, screen: CGRect(x: 0.16, y: 0.07, width: 0.68, height: 0.30), wheel: 0.76, wheelY: 0.71, button: 0.33)
        case .classic, .generic:
            Layout(corner: 0.09, screen: CGRect(x: 0.10, y: 0.06, width: 0.80, height: 0.36), wheel: 0.62, wheelY: 0.71, button: 0.36)
        case .nano1:
            Layout(corner: 0.05, screen: CGRect(x: 0.06, y: 0.035, width: 0.86, height: 0.22), wheel: 0.80, wheelY: 0.56, button: 0.45)
        case .nano2:
            Layout(corner: 0.07, screen: CGRect(x: 0.09, y: 0.07, width: 0.82, height: 0.33), wheel: 0.60, wheelY: 0.70, button: 0.40)
        case .nano3:
            Layout(corner: 0.12, screen: CGRect(x: 0.09, y: 0.06, width: 0.82, height: 0.43), wheel: 0.52, wheelY: 0.73, button: 0.48)
        case .nano4:
            Layout(corner: 0.07, screen: CGRect(x: 0.08, y: 0.055, width: 0.84, height: 0.45), wheel: 0.78, wheelY: 0.775, button: 0.42)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let layout = layout
        let colors = Palette(finish: finish, shape: shape)
        // The outline entirely inside: at the edge of the canvas the sides lost half the line
        // (clipped), and the rounded corners did not - the corners came out brighter,
        // like bumpers.
        let edgeWidth = max(0.5, w * 0.012)
        let bodyRect = CGRect(origin: .zero, size: size).insetBy(dx: edgeWidth / 2, dy: edgeWidth / 2)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: w * layout.corner - edgeWidth / 2, style: .continuous)
        // Aluminum: a light gradient from top to bottom.
        context.fill(bodyPath, with: .linearGradient(Gradient(colors: [colors.bodyTop, colors.bodyBottom]),
                                                     startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
        context.stroke(bodyPath, with: .color(colors.edge), lineWidth: edgeWidth)

        // The screen: almost the full width, a thin dark glass frame.
        let screen = CGRect(x: w * layout.screen.minX, y: h * layout.screen.minY,
                            width: w * layout.screen.width, height: h * layout.screen.height)
        context.fill(Path(roundedRect: screen, cornerRadius: w * 0.015), with: .color(colors.bezel))
        let glass = screen.insetBy(dx: max(0.6, w * 0.022), dy: max(0.6, w * 0.022))
        // iPods 1G-4G and mini: a monochrome display, gray-green.
        let screenColors = shape.monoScreen
            ? [Color(red: 0.66, green: 0.69, blue: 0.62), Color(red: 0.52, green: 0.55, blue: 0.48)]
            : [Color(white: 0.27), Color(white: 0.13)]
        context.fill(Path(glass),
                     with: .linearGradient(Gradient(colors: screenColors),
                                           startPoint: CGPoint(x: glass.minX, y: glass.minY),
                                           endPoint: CGPoint(x: glass.maxX, y: glass.maxY)))

        // The wheel and the center button in the case color.
        let diameter = w * layout.wheel
        let center = CGPoint(x: w / 2, y: h * layout.wheelY)
        let wheel = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.fill(Path(ellipseIn: wheel), with: .color(colors.wheel))
        context.stroke(Path(ellipseIn: wheel), with: .color(colors.edge.opacity(0.45)), lineWidth: max(0.4, w * 0.006))
        let inset = diameter * (1 - layout.button) / 2
        let button = wheel.insetBy(dx: inset, dy: inset)
        // iPod 1G/2G: a ring with four separate buttons around the wheel.
        if shape == .early {
            let inner = wheel.insetBy(dx: diameter * 0.11, dy: diameter * 0.11)
            context.stroke(Path(ellipseIn: inner), with: .color(colors.edge.opacity(0.5)), lineWidth: max(0.4, w * 0.006))
            for angle in [45.0, 135.0, 225.0, 315.0] {
                let r = angle * .pi / 180
                var cut = Path()
                cut.move(to: CGPoint(x: center.x + inner.width / 2 * cos(r), y: center.y + inner.width / 2 * sin(r)))
                cut.addLine(to: CGPoint(x: center.x + diameter / 2 * cos(r), y: center.y + diameter / 2 * sin(r)))
                context.stroke(cut, with: .color(colors.edge.opacity(0.5)), lineWidth: max(0.4, w * 0.006))
            }
        }
        context.fill(Path(ellipseIn: button), with: colors.button.map { .color($0) } ?? .linearGradient(
            Gradient(colors: [colors.bodyTop, colors.bodyBottom]),
            startPoint: CGPoint(x: button.minX, y: button.minY), endPoint: CGPoint(x: button.maxX, y: button.maxY)))
        context.stroke(Path(ellipseIn: button), with: .color(colors.edge.opacity(0.35)), lineWidth: max(0.3, w * 0.005))

        // iPod 3G: a row of four round buttons between the screen and the wheel,
        // lit in orange; the wheel without labels.
        if shape == .third {
            let size = w * 0.17
            for x in [0.19, 0.40, 0.60, 0.81] {
                let key = CGRect(x: w * x - size / 2, y: h * 0.465 - size / 2, width: size, height: size)
                context.fill(Path(ellipseIn: key), with: .color(colors.wheel))
                context.stroke(Path(ellipseIn: key), with: .color(colors.edge.opacity(0.5)), lineWidth: max(0.3, w * 0.005))
                if w >= 40 {
                    let dot = size * 0.32
                    context.fill(Path(roundedRect: CGRect(x: key.midX - dot / 2, y: key.midY - dot * 0.18, width: dot, height: dot * 0.36),
                                      cornerRadius: dot * 0.1), with: .color(Color(red: 0.95, green: 0.45, blue: 0.25)))
                }
            }
            return
        }

        // Labels on the wheel (MENU, back, forward, play) only where they
        // can be read - in a 40 pt icon they would be noise.
        guard diameter >= 34 else { return }
        let ring = diameter * (1 + layout.button) / 4   // the ring's center
        let glyph = diameter * 0.075
        let ink = GraphicsContext.Shading.color(colors.label)
        context.draw(Text("MENU").font(.system(size: glyph * 1.15, weight: .semibold)).foregroundColor(colors.label),
                     at: CGPoint(x: center.x, y: center.y - ring))
        func skip(_ direction: CGFloat, at x: CGFloat) {
            var path = Path()
            for k in 0..<2 {
                let ox = x + direction * CGFloat(k) * glyph * 0.55
                path.move(to: CGPoint(x: ox - direction * glyph * 0.3, y: center.y - glyph * 0.35))
                path.addLine(to: CGPoint(x: ox + direction * glyph * 0.25, y: center.y))
                path.addLine(to: CGPoint(x: ox - direction * glyph * 0.3, y: center.y + glyph * 0.35))
                path.closeSubpath()
            }
            path.addRect(CGRect(x: x + direction * glyph * 0.95 - glyph * 0.06, y: center.y - glyph * 0.35,
                                width: glyph * 0.12, height: glyph * 0.7))
            context.fill(path, with: ink)
        }
        skip(-1, at: center.x - ring + glyph * 0.3)
        skip(1, at: center.x + ring - glyph * 0.3)
        var play = Path()
        let py = center.y + ring
        play.move(to: CGPoint(x: center.x - glyph * 0.65, y: py - glyph * 0.35))
        play.addLine(to: CGPoint(x: center.x - glyph * 0.05, y: py))
        play.addLine(to: CGPoint(x: center.x - glyph * 0.65, y: py + glyph * 0.35))
        play.closeSubpath()
        play.addRect(CGRect(x: center.x + glyph * 0.12, y: py - glyph * 0.35, width: glyph * 0.14, height: glyph * 0.7))
        play.addRect(CGRect(x: center.x + glyph * 0.42, y: py - glyph * 0.35, width: glyph * 0.14, height: glyph * 0.7))
        context.fill(play, with: ink)
    }
}

/// Colors of the case, the wheel and the button. Approximate aluminum and plastic tones,
/// chosen for the app's dark background - not a reproduction of photos.
private struct Palette {
    let bodyTop, bodyBottom, edge, bezel, wheel, label: Color
    /// The center button; `nil` - in the case color (nano and classic aluminum).
    let button: Color?

    init(finish: IPodCatalog.Finish?, shape: IPodGraphic.Shape) {
        func c(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        func shade(_ hex: UInt32, _ factor: Double) -> UInt32 {
            let r = UInt32(Double((hex >> 16) & 0xFF) * factor), g = UInt32(Double((hex >> 8) & 0xFF) * factor), b = UInt32(Double(hex & 0xFF) * factor)
            return r << 16 | g << 8 | b
        }
        bezel = c(0x1C1D1F)
        switch finish {
        case .black?:
            // Black: the wheel almost in the case color, light labels (nano 2G, 4G, 5G).
            bodyTop = c(0x3A3B3E); bodyBottom = c(0x232427)
            wheel = shape == .video || shape == .nano1 ? c(0x34353A) : c(0x1E1F21)
            button = shape == .video || shape == .nano1 ? c(0x232427) : nil
            label = c(0xE6E6E6)
        case .u2?:
            bodyTop = c(0x2F3033); bodyBottom = c(0x1E1F21); wheel = c(0xB3202A); button = c(0x2B2C2F); label = c(0xE6E6E6)
        case .white?:
            bodyTop = c(0xF6F6F4); bodyBottom = c(0xDCDCD9)
            if shape.greyWheelOnWhite {
                // 4G, photo, 5G, nano 1G: a gray wheel, a white button, white labels.
                wheel = shape == .nano1 ? c(0xB9BBC6) : c(0xCDCECF); button = c(0xF8F8F6); label = c(0xF8F8F6)
            } else {
                wheel = c(0xF8F8F6); button = c(0xEFEFEC); label = c(0xA0A0A0)
            }
        case nil:
            // Unknown color: a gray case, so as not to pretend it was recognized.
            bodyTop = c(0x8C8F94); bodyBottom = c(0x686B70); wheel = c(0xA9ACB0); button = c(0x86898E); label = c(0x6A6D72)
        default:
            let tint: UInt32 = switch finish {
            case .silver?: shape == .mini ? 0xC9CCD0 : 0xD9DCE0
            case .blue?: shape == .mini ? 0x3FA7C9 : 0x4A9AD8
            case .pink?: 0xE8A2BE
            case .green?: 0x9CC968
            case .gold?: 0xD6B98C
            case .red?: 0xC22238
            case .orange?: 0xE9893A
            case .purple?: 0x6A5CD6
            case .yellow?: 0xE6D25C
            default: 0xB8BCC2
            }
            bodyTop = c(tint); bodyBottom = c(shade(tint, finish == .silver ? 0.80 : 0.80))
            if shape == .mini {
                // mini: a light wheel, a gray button, labels in the case color.
                wheel = c(0xEDEDEB); button = c(0xD9DAD8); label = c(shade(tint, 0.85))
            } else {
                wheel = shape == .classic ? c(0xE4E5E7) : c(0xF4F4F2); button = nil; label = c(0x9A9DA2)
            }
        }
        edge = finish == .black || finish == .u2 ? c(0x55565A) : c(0x7D8086)
    }
}

extension IPodGraphic {
    /// The drawing for a connected iPod: the catalog, and without it the USB family.
    init(device: IPodDevice) {
        let entry = device.catalogEntry
        self.init(shape: Shape(generation: entry?.generation, usbFamily: device.usb?.familyName), finish: entry?.finishOrDefault)
    }

    /// The drawing for an item in the chooser (also `--demo-ipod`).
    init(choice: IPodChoice) {
        self.init(shape: Shape(generation: choice.generation, usbFamily: choice.modelName), finish: choice.finish)
    }
}

/// `--ipod-gallery <file.png>`: all iPod drawings in two sizes
/// (40 pt as in the chooser, 120 pt) on the sidebar background - for reviewing
/// the drawings without connecting every model. Writes a PNG and ends the process.
enum IPodGallery {
    static let variants: [(String, IPodGraphic.Shape, IPodCatalog.Finish?)] = [
        ("1G/2G", .early, .white), ("3G", .third, .white), ("4G", .fourth, .white), ("4G U2", .fourth, .u2),
        ("photo", .photo, .white), ("5G white", .video, .white), ("5G black", .video, .black),
        ("mini silver", .mini, .silver), ("mini blue", .mini, .blue), ("mini pink", .mini, .pink),
        ("mini green", .mini, .green), ("mini gold", .mini, .gold),
        ("nano 1G white", .nano1, .white), ("nano 1G black", .nano1, .black),
        ("classic black", .classic, .black), ("classic silver", .classic, .silver),
        ("nano 2G silver", .nano2, .silver), ("nano 2G pink", .nano2, .pink),
        ("nano 2G green", .nano2, .green), ("nano 2G blue", .nano2, .blue),
        ("nano 2G red", .nano2, .red), ("nano 2G black", .nano2, .black),
        ("nano 3G silver", .nano3, .silver), ("nano 3G black", .nano3, .black), ("nano 3G blue", .nano3, .blue),
        ("nano 3G green", .nano3, .green), ("nano 3G red", .nano3, .red),
        ("nano 4G silver", .nano4, .silver), ("nano 4G black", .nano4, .black), ("nano 4G purple", .nano4, .purple),
        ("nano 4G blue", .nano4, .blue), ("nano 4G green", .nano4, .green), ("nano 4G yellow", .nano4, .yellow),
        ("nano 4G orange", .nano4, .orange), ("nano 4G pink", .nano4, .pink), ("nano 4G red", .nano4, .red),
        ("unknown", .generic, nil),
    ]

    @MainActor static func render(to output: URL) {
        let content = LazyVGrid(columns: Array(repeating: GridItem(.fixed(150), spacing: 24, alignment: .bottom), count: 6),
                                alignment: .leading, spacing: 26) {
            ForEach(variants.indices, id: \.self) { i in
                let (name, shape, finish) = variants[i]
                VStack(spacing: 10) {
                    IPodGraphic(shape: shape, finish: finish).frame(height: 190)
                    IPodGraphic(shape: shape, finish: finish).frame(width: 40, height: 46)
                    Text(name).font(.theme(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .background(Color(red: 0.13, green: 0.13, blue: 0.14))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: output)
        }
        exit(0)
    }
}
