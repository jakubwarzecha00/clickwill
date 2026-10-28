import Foundation

func formatted(bytes: Int64) -> String {
    guard bytes > 0 else { return "0 B" }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

/// An aligned column of labels - more readable than padding with spaces at the call site.
func report(_ title: String, _ rows: [(String, String)]) {
    let width = rows.map(\.0.count).max() ?? 0
    print(title)
    for (label, value) in rows {
        print("  " + label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + value)
    }
}
