import Foundation
import Testing
@testable import ITDBKit

private enum Fixture {
    static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }
    static func header(type: UInt32, bodyCount: Int) -> [UInt8] {
        var bytes = Array("mhod".utf8) + u32(24) + u32(UInt32(24 + bodyCount)) + u32(type)
        bytes += [UInt8](repeating: 0, count: 24 - bytes.count)
        return bytes
    }
    static func index(criterion: UInt32, _ entries: [UInt32]) -> Mhod {
        var body = u32(criterion) + u32(UInt32(entries.count))
        body += [UInt8](repeating: 0, count: BrowseIndex.preambleLength - body.count)
        for entry in entries { body += u32(entry) }
        return Mhod(type: MhodType(rawValue: 52), text: nil,
                    rawHeader: header(type: 52, bodyCount: body.count), rawBody: body)
    }
    static func jump(criterion: UInt32, _ entries: [(UInt32, UInt32, UInt32)]) -> Mhod {
        var body = u32(criterion) + u32(UInt32(entries.count))
        body += [UInt8](repeating: 0, count: AlphabetJumpTable.preambleLength - body.count)
        for entry in entries { body += u32(entry.0) + u32(entry.1) + u32(entry.2) }
        return Mhod(type: MhodType(rawValue: 53), text: nil,
                    rawHeader: header(type: 53, bodyCount: body.count), rawBody: body)
    }
}

@Suite("Removing tracks")
struct TrackRemovalTests {

    /// The mapping for a library of `count` tracks with the positions `removed` removed.
    private func mapping(count: Int, removed: Set<Int>) -> [Int?] {
        var result = [Int?](repeating: nil, count: count)
        var next = 0
        for position in 0..<count where !removed.contains(position) {
            result[position] = next
            next += 1
        }
        return result
    }

    @Test("positions greater than a removed one move down")
    func shiftsHigherPositions() throws {
        let table = Fixture.index(criterion: 4, [3, 1, 0, 2])
        let result = try ITLibrary.remapping([table], through: mapping(count: 4, removed: [1]))
        let rebuilt = try #require(BrowseIndex(mhod: result[0]))

        // The removed track 1 drops out; 3 and 2 move down by one.
        #expect(rebuilt.entries == [2, 0, 1])
        #expect(rebuilt.isPermutation(of: 3))
    }

    @Test("removing several tracks leaves a full permutation")
    func staysPermutation() throws {
        let entries: [UInt32] = [7, 2, 5, 0, 9, 3, 8, 1, 6, 4]
        let table = Fixture.index(criterion: 4, entries)
        let result = try ITLibrary.remapping([table], through: mapping(count: 10, removed: [0, 4, 9]))
        let rebuilt = try #require(BrowseIndex(mhod: result[0]))

        #expect(rebuilt.entries.count == 7)
        #expect(rebuilt.isPermutation(of: 7))
    }

    @Test("nothing removed means the table is unchanged")
    func identityMapping() throws {
        let table = Fixture.index(criterion: 4, [3, 1, 0, 2])
        let result = try ITLibrary.remapping([table], through: mapping(count: 4, removed: []))
        #expect(result[0].rawBody == table.rawBody)
    }

    @Test("the jump bar loses as much as was lost in the letter's range")
    func jumpTableShrinks() throws {
        // A table of 6 positions: letter A at 0-2, B at 3-5.
        let table = Fixture.index(criterion: 4, [0, 1, 2, 3, 4, 5])
        let jump = Fixture.jump(criterion: 4, [(65, 0, 3), (66, 3, 3)])
        // We remove tracks 1 (in A) and 4 and 5 (in B).
        let result = try ITLibrary.remapping([table, jump], through: mapping(count: 6, removed: [1, 4, 5]))

        let rebuilt = try #require(AlphabetJumpTable(mhod: result[1]))
        #expect(rebuilt.entries.count == 2)
        #expect(rebuilt.entries[0].character == "A")
        #expect(rebuilt.entries[0].start == 0)
        #expect(rebuilt.entries[0].count == 2)
        #expect(rebuilt.entries[1].character == "B")
        #expect(rebuilt.entries[1].start == 2)
        #expect(rebuilt.entries[1].count == 1)
    }

    @Test("a letter without tracks disappears from the bar")
    func emptyLetterDisappears() throws {
        let table = Fixture.index(criterion: 4, [0, 1, 2, 3])
        let jump = Fixture.jump(criterion: 4, [(65, 0, 2), (66, 2, 1), (67, 3, 1)])
        // We remove the whole range of the letter B.
        let result = try ITLibrary.remapping([table, jump], through: mapping(count: 4, removed: [2]))

        let rebuilt = try #require(AlphabetJumpTable(mhod: result[1]))
        #expect(rebuilt.entries.map(\.character) == ["A", "C"])
        #expect(rebuilt.entries[1].start == 2)
        #expect(rebuilt.entries[1].count == 1)
    }

    @Test("records of another type pass through untouched")
    func leavesOtherMhods() throws {
        let text = Mhod.text(type: .album, value: "UTOPIA")
        let result = try ITLibrary.remapping([text], through: mapping(count: 4, removed: [1]))
        #expect(result[0].rawBody == text.rawBody)
        #expect(result[0].rawHeader == text.rawHeader)
    }
}

@Suite("Removing and the album list")
struct TrackRemovalAlbumTests {

    @Test("an album that lost all its tracks disappears from the album list")
    func orphanAlbumRecordRemoved() throws {
        let library = try LibraryFixture.standard()
        let before = library.albums.count
        // Currents has two tracks - after both, the album has none.
        let currents = library.tracks.filter { $0.album == "Currents" }.map(\.uniqueID)
        let after = try library.removingTracks(uniqueIDs: Set(currents))

        #expect(after.albums.count == before - 1)
        #expect(!after.albums.contains { $0.title == "Currents" })
    }

    @Test("an album that kept a track stays on the list")
    func albumWithSurvivorsKept() throws {
        let library = try LibraryFixture.standard()
        let before = library.albums.count
        let one = library.tracks.first { $0.album == "The Bends" }!.uniqueID
        let after = try library.removingTracks(uniqueIDs: [one])

        #expect(after.albums.count == before)
        #expect(after.albums.contains { $0.title == "The Bends" })
    }

    @Test("the numbering of the remaining album records does not change")
    func remainingIndicesUnchanged() throws {
        let library = try LibraryFixture.standard()
        let currents = library.tracks.filter { $0.album == "Currents" }.map(\.uniqueID)
        let after = try library.removingTracks(uniqueIDs: Set(currents))

        for album in after.albums {
            let original = library.albums.first { $0.title == album.title }
            #expect(album.index == original?.index)
        }
    }
}
