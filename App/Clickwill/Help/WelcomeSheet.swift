import SwiftUI

/// The first launch: one welcome page as in Apple's apps
/// (Pages, Keynote, Xcode) - an icon, a title, four things to know
/// before editing an iPod, one button. The HIG recommends a short introduction; the rest
/// of the knowledge goes into TipKit tips where it is needed. The texts are in the first
/// person and without en dashes.
///
/// The most important row is the one about Music - that is something the app cannot guard by itself.
/// Preflight blocks writing while Music is open, but it does not protect changes already
/// written: Music open on the next connection rebuilds the iPod's menu tables
/// and the order set in Clickwill disappears (measured twice).
/// Music can also launch by itself after the dock
/// is reset.
struct WelcomeSheet: View {
    static let seenKey = "clickwill.welcome.seen"
    @AppStorage(WelcomeSheet.seenKey) private var seen = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Welcome to Clickwill")
                .font(.largeTitle.bold())
                .padding(.top, 14)
            Text("Thanks for trying the \(AboutFacts.stage ?? "app"). Here's what I'd like you to know before you edit your iPod.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 20) {
                row("music.note.slash", .red,
                    "Keep Music closed",
                    "When Music opens with your iPod connected, it can reset the album and song order. If it opens by itself, quit it with Command\u{2011}Q.")
                row("tray.and.arrow.down", .accentColor,
                    "Nothing changes until you write",
                    "Your edits wait as pending changes. The iPod changes only when you choose Write to iPod.")
                row("clock.arrow.circlepath", .green,
                    "A backup before every write",
                    "You can restore an earlier library from Backups. Keep your own copy of the music files you care about.")
                row("ipod", .secondary,
                    "Made for iPod classic and nano",
                    "Clickwill edits the iPod classic and the iPod nano (2nd to 4th generation). Other iPods open read-only for now.")
            }
            .padding(.top, 30)

            Button("Continue") {
                seen = true
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 34)
        }
        .padding(EdgeInsets(top: 36, leading: 48, bottom: 32, trailing: 48))
        .frame(width: 540)
        .sheetKeyFocus()
    }

    private func row(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.symbol(.xLarge))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
