import Foundation
import Testing
@testable import ITDBKit
@testable import ClickwillModel

/// Decisions of the add sheet: what goes into the queue, what gets replaced,
/// what is skipped - on a fake iPod with the album The Bends (Planet Telex, Bones, Just).
@Suite("Add session")
@MainActor
struct ImportSessionTests {

    private func file(_ title: String, album: String = "The Bends", artist: String = "Radiohead",
                      milliseconds: UInt32 = 180_000, verdict: AudioCompatibility.Verdict = .supported) -> AudioImport.Candidate {
        let draft = TrackDraft(title: title, artist: artist, albumArtist: artist, album: album,
                               durationMilliseconds: milliseconds, sizeBytes: 1_000, kind: .mp3, relativePath: "")
        return AudioImport.Candidate(url: URL(fileURLWithPath: "/tmp/import-\(title).mp3"), draft: draft, verdict: verdict,
                                     formatLabel: "MP3", artwork: nil)
    }

    private func session(on rig: WriteTests.Rig, _ files: [AudioImport.Candidate]) -> ImportSession {
        var session = ImportSession(existing: rig.model.songIndex())
        session.add(files, problems: [])
        session.refreshMatches(in: rig.model)
        return session
    }

    @Test("files from one album are one group; the same file a second time is not duplicated; an unplayable one goes to the notices")
    func groupingAndDuplicateFiles() {
        var session = ImportSession(existing: SongIndex())
        let a = file("One", album: "Loveless"), b = file("Two", album: "Loveless")
        let hopeless = file("Three", album: "Loveless", verdict: .rejected(reason: "no"))
        session.add([a, b, hopeless], problems: [AudioImport.ImportError.unreadable(URL(fileURLWithPath: "/tmp/x.flac"))])
        session.add([file("One", album: "Loveless")], problems: [])
        #expect(session.albums.count == 1)
        #expect(session.candidates.count == 2)
        #expect(session.problems.count == 2)
        guard case .unreadable(AudioImport.ImportError.unreadable)? = session.problems.first,
              case .cannotPlay("Three", "no")? = session.problems.last else {
            Issue.record("\(session.problems)"); return
        }

        session.remove(a.id)
        #expect(session.candidates.map(\.draft.title) == ["Two"])
        #expect(session.albums.count == 1)
    }

    @Test("a song that already exists, as a separate album: skipped until the user adds it anyway")
    func duplicateSkippedUnlessAddedAnyway() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let bones = file("Bones")
        var session = session(on: rig, [bones])
        let group = session.group(of: bones)
        #expect(session.matches[group] != nil, "matches The Bends")
        #expect(!session.showsDuplicates(bones), "with a replacement the duplicate does not matter")
        session.choose(.separate, for: group)
        #expect(session.place(of: bones) == .onIPod)
        #expect(session.toAdd(in: rig.model).isEmpty)
        #expect(session.skippedCount == 1)
        #expect(session.isLeftOut(bones))

        session.toggleAddAnyway(bones)
        #expect(session.toAdd(in: rig.model).map(\.id) == [bones.id])
        #expect(session.skippedCount == 0)
    }

    @Test("an album that already exists: replacing files by default, a new track attached to it; skip; a separate album")
    func albumAlreadyOnIPod() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let extra = file("High and Dry", album: "The Bends (Remaster)", artist: "")
        var files = ["Planet Telex", "Bones", "Just"].map { file($0, album: "The Bends (Remaster)", artist: "") }
        files.append(extra)
        var session = session(on: rig, files)
        let group = try #require(session.albums.first?.id)
        let match = try #require(session.matches[group])
        #expect(match.album.title == "The Bends")
        #expect(match.pairs.count == 3)

        #expect(session.choice(for: group) == .replace)
        #expect(session.replaceCount == 3)
        let added = session.toAdd(in: rig.model)
        #expect(added.map(\.id) == [extra.id])
        #expect(added.first?.draft.album == "The Bends", "attached to the album on the iPod, not as a new one")
        #expect(added.first?.draft.artist == "Radiohead")

        session.choose(.skip, for: group)
        #expect(session.toAdd(in: rig.model).isEmpty)
        #expect(session.replaceCount == 0)
        #expect(files.allSatisfy(session.isLeftOut))

        session.choose(.separate, for: group)
        #expect(session.replaceCount == 0)
        #expect(session.toAdd(in: rig.model).count == 4, "a separate album under the name from the files")
    }

    @Test("confirming queues the additions and replacements; a second one returns refusals instead of losing them")
    func commitReturnsRefusals() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        var files = ["Planet Telex", "Bones", "Just"].map { file($0) }
        files.append(file("High and Dry"))
        let session = session(on: rig, files)

        let first = session.commit(to: rig.model)
        #expect(first.refused.isEmpty)
        #expect(first.queued == 4)
        #expect(rig.model.changes.fileImports.count == 3)
        #expect(rig.model.changes.additions.count == 1)

        let again = session.commit(to: rig.model)
        #expect(again.refused.contains { if case .alreadyQueued = $0.reason { true } else { false } }, "\(again.refused)")
        #expect(again.queued == 3, "replacements replace the previous ones, a refusal only for the addition")
    }

    @Test("the same file in a second sheet: already in the queue; added anyway - a refusal instead of a second copy")
    func sameFileInSecondSheet() async throws {
        let rig = try await WriteTests.rig(); defer { rig.cleanUp() }
        let song = file("High and Dry", album: "Planet Telex B-Sides")
        #expect(session(on: rig, [song]).commit(to: rig.model).refused.isEmpty)

        let again = file("High and Dry", album: "Planet Telex B-Sides")
        var second = session(on: rig, [again])
        #expect(second.place(of: again) == .queued)
        #expect(second.toAdd(in: rig.model).isEmpty)
        second.toggleAddAnyway(again)
        let commit = second.commit(to: rig.model)
        guard commit.refused.count == 1, case .alreadyQueued? = commit.refused.first?.reason else {
            Issue.record("\(commit.refused)"); return
        }
        #expect(commit.queued == 0, "nothing was added - the sheet does not say \"the rest is on the list\"")
        #expect(rig.model.changes.additions.count == 1)
    }

    @Test("corrections before the write: a track field and the album fields of the whole group, artwork for the group")
    func editsBeforeCommit() {
        var session = ImportSession(existing: SongIndex())
        let a = file("One", album: "Loveless"), b = file("Two", album: "Loveless")
        session.add([a, b], problems: [])
        let group = session.group(of: a)
        session.edit(a.id) { $0.title = "Only Shallow" }
        session.editGroup(group) { $0.album = "Loveless (Remaster)" }
        session.setCover(URL(fileURLWithPath: "/tmp/cover.png"), for: group)
        #expect(session.draft(of: a.id)?.title == "Only Shallow")
        #expect(session.candidates.allSatisfy { $0.draft.album == "Loveless (Remaster)" })
        #expect(session.candidates.allSatisfy { $0.chosenCover != nil })
        #expect(session.albums.count == 1, "renaming the album does not split the group")
        #expect(session.songsDiffer(in: group, from: "Someone") == true)
    }
}
