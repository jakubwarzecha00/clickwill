import SwiftUI
import AppKit
import ClickwillModel

/// A track row field edited in place.
enum TrackRowField { case title, number }

/// A track row in the album list. `RowMenu`: the contents of the row menu - shared
/// by the three dots and the right mouse button.
struct TrackRowView<RowMenu: View>: View {
    let row: TrackRow
    let selected: Bool
    /// This track is playing now in the player bar.
    var playing = false
    var editing: TrackRowField? = nil
    /// The name of the file waiting in the queue for an entry without a file; `nil` when nothing
    /// was chosen. The row must say so right away - otherwise the file choice
    /// would look like it failed until the write.
    var restoring: String? = nil
    /// The name of the file that will replace the current one. Separate from `restoring`, because
    /// it promises something else: here the old file disappears from the iPod after the write.
    var replacing: String? = nil
    var play: () -> Void = {}
    var select: () -> Void = {}
    let menu: () -> RowMenu
    var commitTitle: (String) -> Void = { _ in }
    var commitNumber: (UInt32) -> Void = { _ in }
    var cancelEdit: () -> Void = {}
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.theme(.caption)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
    }

    private var ellipsis: some View {
        Image(systemName: "ellipsis").font(.theme(.callout, weight: .semibold))
            .foregroundStyle(hovering || selected ? Theme.fg : Theme.f3)
            .frame(width: TrackColumns.menu, height: 22).contentShape(Rectangle())
    }

    var body: some View {
        HStack(spacing: TrackColumns.spacing) {
            // The number column shows a Play button on hover, and a speaker for the playing
            // track - otherwise nothing says the row can be previewed.
            ZStack(alignment: .trailing) {
                if editing == .number {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain).font(.theme(.body)).monospacedDigit().multilineTextAlignment(.trailing)
                        .focused($fieldFocused)
                        .onSubmit { commitNumber(UInt32(draft.trimmingCharacters(in: .whitespaces)) ?? 0) }
                        .onExitCommand(perform: cancelEdit)
                        .onAppear { draft = row.number == 0 ? "" : "\(row.number)"; fieldFocused = true }
                } else if playing {
                    Image(systemName: "speaker.wave.2.fill").font(.theme(.caption)).foregroundStyle(Theme.accent)
                } else if hovering, !row.fileMissing {
                    Image(systemName: "play.fill").font(.theme(.caption)).foregroundStyle(Theme.fg)
                        .frame(width: 22, height: 22).contentShape(Rectangle())
                        .highPriorityGesture(TapGesture().onEnded(play))
                        .help("Play from here")
                } else {
                    Text(row.number == 0 ? "–" : "\(row.number)")
                        .font(.theme(.body)).foregroundStyle(Theme.f2).monospacedDigit()
                }
            }
            .frame(width: TrackColumns.number, alignment: .trailing)
            HStack(spacing: 8) {
                if editing == .title {
                    TextField("Title", text: $draft)
                        .textFieldStyle(.plain).font(.theme(.row))
                        .focused($fieldFocused)
                        .onSubmit { commitTitle(draft) }
                        .onExitCommand(perform: cancelEdit)
                        .onAppear { draft = row.title; fieldFocused = true }
                } else {
                    Text(row.displayTitle).font(.theme(.row)).lineLimit(1)
                }
                if let replacing {
                    badge("Replaced by \(replacing) when you write", Theme.accent)
                } else if let restoring {
                    badge("\(restoring): comes back when you write", Theme.ok)
                } else if row.fileMissing {
                    badge("No file, the iPod skips it", Theme.warn)
                } else if row.unplayable {
                    badge("\(row.formatLabel ?? "this format"): the iPod skips it", Theme.destructive)
                        .help(row.formatVerdict?.reason ?? "")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text("\(row.playCount)").frame(width: TrackColumns.plays, alignment: .trailing).font(.theme(.body)).foregroundStyle(Theme.f2).monospacedDigit()
            Text(row.duration.clockLabel).frame(width: TrackColumns.time, alignment: .trailing).font(.theme(.body)).foregroundStyle(Theme.f2).monospacedDigit()
            // Three dots: the same menu as under the right mouse button - a sign that
            // the row can be edited.
            Menu { menu() } label: { ellipsis }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: TrackColumns.menu, height: 22)
        }
        .padding(EdgeInsets(top: TrackColumns.rowPadding, leading: TrackColumns.inset,
                            bottom: TrackColumns.rowPadding, trailing: TrackColumns.inset))
        .background(selected ? Theme.sel : (hovering ? Color.white.opacity(0.08) : .clear), in: RoundedRectangle(cornerRadius: 6))
        .trackRowDivider(hidden: selected || hovering)
        .opacity(row.fileMissing && restoring == nil ? 0.55 : 1)
        // Gestures on the whole row (that is how dragging works in List); the Play button
        // has a higher-priority gesture, so it does not wait for the double-click to be resolved.
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if editing == nil { play() } }
        .onTapGesture(count: 1) { if editing == nil { select() } }
        .onHover { hovering = $0 }
    }
}
