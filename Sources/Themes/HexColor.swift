import SwiftUI

/// Colors in a theme file: `#RRGGBB` or `#RRGGBBAA`, sRGB, 8 bits per channel.
public enum HexColor {
    /// Nil for anything but a hash and 6 or 8 hex digits (`#RGB` included).
    public static func color(_ text: String) -> Color? {
        guard let channels = channels(text) else { return nil }
        return Color(.sRGB, red: channels.r, green: channels.g, blue: channels.b, opacity: channels.a)
    }

    /// The same text a file keeps: upper case, alpha only when the color is transparent.
    public static func normalized(_ text: String) -> String? {
        guard let channels = channels(text) else { return nil }
        return string(r: channels.r, g: channels.g, b: channels.b, a: channels.a)
    }

    /// The color as the file keeps it, as drawn in sRGB. `opaque` drops its alpha.
    public static func string(_ color: Color, opaque: Bool = false) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        return string(r: Double(resolved.red), g: Double(resolved.green), b: Double(resolved.blue),
                      a: opaque ? 1 : Double(resolved.opacity))
    }

    private static func string(r: Double, g: Double, b: Double, a: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        let rgb = String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        return byte(a) == 255 ? rgb : rgb + String(format: "%02X", byte(a))
    }

    private static func channels(_ text: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        let digits = Array(text.utf8)
        guard digits.first == UInt8(ascii: "#"), digits.count == 7 || digits.count == 9 else { return nil }
        var values: [Double] = []
        var index = 1
        while index < digits.count {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else { return nil }
            values.append(Double(high * 16 + low) / 255)
            index += 2
        }
        return (values[0], values[1], values[2], values.count == 4 ? values[3] : 1)
    }

    private static func nibble(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "A")...UInt8(ascii: "F"): Int(byte - UInt8(ascii: "A")) + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): Int(byte - UInt8(ascii: "a")) + 10
        default: nil
        }
    }
}
