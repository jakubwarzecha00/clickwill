import Foundation

// Numbers and strings in a form for the interface.

extension String {
    /// "Today at 2:22" -> "today at 2:22" in the middle of a sentence.
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
    /// "this alpha" -> "This alpha".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension TimeInterval {
    var minutesLabel: String {
        let total = Int(self.rounded())
        return "\(total / 60) min"
    }
    var clockLabel: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Int64 {
    var gigabytes: String { String(format: "%.1f GB", Double(self) / 1_000_000_000) }
}
