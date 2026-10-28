import SwiftUI

/// A text field that looks like a label until you enter it.
/// The same idea as in the album track list - editing should be available, but must not
/// turn browsing into a form. A native field without a frame; the system
/// focus ring appears while editing.
struct ImportField: View {
    @Binding var text: String
    let placeholder: String
    var font: Font = .body
    var width: CGFloat? = nil
    var alignment: TextAlignment = .leading

    var body: some View {
        // In a Form the field shows its own label on the left and the value on the right -
        // here the label is unnecessary, the placeholder in an empty field is enough. The placeholder
        // in italics and lighter: a gray "Artist" looked like an entered artist
        // (visible on albums without tags).
        TextField(placeholder, text: $text, prompt: Text(placeholder).italic().foregroundStyle(.tertiary))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(font)
            .multilineTextAlignment(alignment)
            .frame(width: width, alignment: alignment == .trailing ? .trailing : .leading)
            .frame(maxWidth: width == nil ? 420 : nil, alignment: .leading)
    }
}
