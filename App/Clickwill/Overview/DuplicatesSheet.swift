import SwiftUI
import ClickwillModel

/// Songs that are on the iPod several times, and merging them.
/// Nothing disappears right away: the merge goes onto the change list like deleting
/// an album, and the files disappear from the iPod only after "Write to iPod".
struct DuplicatesSheet: View {
    let groups: [DuplicateGroup]

    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Groups unchecked by the user - by default we merge all of them.
    @State private var skipped: Set<UInt32> = []
    @State private var keepCopies = true
    @State private var error: String?

    /// `~/Music/Clickwill/Removed Duplicates` - next to ripped discs, without asking for a folder.
    static var archive: URL {
        CDRipper.defaultRoot.appendingPathComponent("Removed Duplicates", isDirectory: true)
    }

    private var chosen: [DuplicateGroup] { groups.filter { !skipped.contains($0.id) } }
    private var extraCopies: Int { chosen.reduce(0) { $0 + $1.remove.count } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("These songs are on your iPod more than once. I keep one copy of each and remove the others. The copy that stays gets their plays, the higher rating and their places in your playlists.")
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Save the removed files to Music › Clickwill › Removed Duplicates", isOn: $keepCopies)
                }
                Section(groups.count == 1 ? "1 song" : "\(groups.count) songs") {
                    ForEach(groups) { group in
                        Toggle(isOn: included(group)) { row(group) }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Duplicate Songs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(extraCopies == 1 ? "Remove 1 Copy" : "Remove \(extraCopies) Copies") { merge() }
                        .disabled(chosen.isEmpty)
                }
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 480, idealHeight: 640)
        .alert("This change couldn't be made", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func row(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(group.title.isEmpty ? "Untitled" : group.title)
            Text([group.artist, group.album].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            Text("Keeps \(describe(group.keep)). Removes \(group.remove.map(describe).joined(separator: "; ")).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func describe(_ copy: DuplicateGroup.Copy) -> String {
        var parts = [copy.format, copy.playCount == 1 ? "1 play" : "\(copy.playCount) plays"]
        if copy.fileMissing { parts.append("no file") }
        return parts.joined(separator: ", ")
    }

    private func included(_ group: DuplicateGroup) -> Binding<Bool> {
        Binding(get: { !skipped.contains(group.id) },
                set: { if $0 { skipped.remove(group.id) } else { skipped.insert(group.id) } })
    }

    private func merge() {
        do {
            try model.mergeDuplicates(chosen, keepCopiesIn: keepCopies ? Self.archive : nil)
            dismiss()
        } catch {
            self.error = ErrorPresenter.message(for: error)
        }
    }
}
