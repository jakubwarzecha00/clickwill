import Foundation
import Testing
@testable import ITDBKit

/// Assembles an `mhod` record of type 52 or 53 from raw bytes.
private enum IndexFixture {
    static func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)]
    }

    static func header(type: UInt32, bodyCount: Int) -> [UInt8] {
        var bytes = Array("mhod".utf8) + u32(24) + u32(UInt32(24 + bodyCount)) + u32(type)
        bytes += [UInt8](repeating: 0, count: 24 - bytes.count)
        return bytes
    }

    /// A browse table: 48 B of preamble, then track positions.
    static func browseIndex(criterion: UInt32, entries: [UInt32]) -> Mhod {
        var body = u32(criterion) + u32(UInt32(entries.count))
        body += [UInt8](repeating: 0, count: BrowseIndex.preambleLength - body.count)
        for entry in entries { body += u32(entry) }
        return Mhod(type: MhodType(rawValue: 52), text: nil,
                    rawHeader: header(type: 52, bodyCount: body.count), rawBody: body)
    }

    /// A jump bar: 16 B of preamble, then letter/start/length triples.
    static func jumpTable(criterion: UInt32, entries: [(UInt32, UInt32, UInt32)]) -> Mhod {
        var body = u32(criterion) + u32(UInt32(entries.count))
        body += [UInt8](repeating: 0, count: AlphabetJumpTable.preambleLength - body.count)
        for entry in entries { body += u32(entry.0) + u32(entry.1) + u32(entry.2) }
        return Mhod(type: MhodType(rawValue: 53), text: nil,
                    rawHeader: header(type: 53, bodyCount: body.count), rawBody: body)
    }
}

@Suite("Browse tables")
struct BrowseIndexTests {

    @Test("the table is reproduced byte for byte")
    func browseIndexRoundTrip() throws {
        let original = IndexFixture.browseIndex(criterion: 4, entries: [3, 1, 0, 2])
        let parsed = try #require(BrowseIndex(mhod: original))

        #expect(parsed.criterion == .album)
        #expect(parsed.entries == [3, 1, 0, 2])

        let rebuilt = parsed.mhod()
        #expect(rebuilt.rawHeader == original.rawHeader)
        #expect(rebuilt.rawBody == original.rawBody)
    }

    @Test("reordering keeps the record length")
    func reorderKeepsLength() throws {
        let original = IndexFixture.browseIndex(criterion: 4, entries: Array(0..<50))
        var parsed = try #require(BrowseIndex(mhod: original))
        parsed.entries.reverse()

        let rebuilt = parsed.mhod()
        #expect(rebuilt.byteCount == original.byteCount)
        #expect(BrowseIndex(mhod: rebuilt)?.entries == Array((0..<50).reversed()))
    }

    @Test("the count in the preamble follows the table, not the value read")
    func countFollowsEntries() throws {
        let original = IndexFixture.browseIndex(criterion: 4, entries: [0, 1, 2, 3])
        var parsed = try #require(BrowseIndex(mhod: original))
        parsed.entries.removeLast()

        let rebuilt = parsed.mhod()
        let reparsed = try #require(BrowseIndex(mhod: rebuilt))
        #expect(reparsed.entries == [0, 1, 2])
        #expect(rebuilt.byteCount == original.byteCount - 4)
    }

    @Test("a permutation is recognized, and a hole rejected")
    func permutationCheck() throws {
        let good = try #require(BrowseIndex(mhod: IndexFixture.browseIndex(criterion: 4, entries: [2, 0, 1])))
        #expect(good.isPermutation(of: 3))

        let duplicated = try #require(BrowseIndex(mhod: IndexFixture.browseIndex(criterion: 4, entries: [0, 0, 1])))
        #expect(!duplicated.isPermutation(of: 3))
    }

    @Test("a record with a length that does not match the count is not accepted")
    func rejectsTruncated() {
        var mhod = IndexFixture.browseIndex(criterion: 4, entries: [0, 1, 2])
        let truncated = Mhod(type: mhod.type, text: nil,
                             rawHeader: mhod.rawHeader, rawBody: Array(mhod.rawBody.dropLast(4)))
        #expect(BrowseIndex(mhod: truncated) == nil)

        mhod = IndexFixture.browseIndex(criterion: 4, entries: [])
        let empty = try? #require(BrowseIndex(mhod: mhod))
        #expect(empty?.entries.isEmpty == true)
    }

    @Test("a record of another type is not a table")
    func rejectsOtherType() {
        let text = Mhod.text(type: .album, value: "DONDA")
        #expect(BrowseIndex(mhod: text) == nil)
        #expect(AlphabetJumpTable(mhod: text) == nil)
    }

    @Test("the jump bar is reproduced byte for byte")
    func jumpTableRoundTrip() throws {
        let original = IndexFixture.jumpTable(
            criterion: 4, entries: [(65, 0, 74), (66, 74, 111), (67, 185, 71)])
        let parsed = try #require(AlphabetJumpTable(mhod: original))

        #expect(parsed.criterion == .album)
        #expect(parsed.entries.count == 3)
        #expect(parsed.entries[1].character == "B")
        #expect(parsed.entries[1].range == 74..<185)

        let rebuilt = parsed.mhod()
        #expect(rebuilt.rawHeader == original.rawHeader)
        #expect(rebuilt.rawBody == original.rawBody)
    }

    @Test("the jump bar gives the letter for a position")
    func jumpTableLookup() throws {
        let parsed = try #require(AlphabetJumpTable(mhod: IndexFixture.jumpTable(
            criterion: 4, entries: [(65, 0, 74), (66, 74, 111), (67, 185, 71)])))

        #expect(parsed.section(containing: 0)?.character == "A")
        #expect(parsed.section(containing: 73)?.character == "A")
        #expect(parsed.section(containing: 74)?.character == "B")
        #expect(parsed.section(containing: 184)?.character == "B")
        #expect(parsed.section(containing: 185)?.character == "C")
        #expect(parsed.section(containing: 999) == nil)
    }
}

@Suite("Jump bar from the layout")
struct JumpTableDerivationTests {

    private func table() throws -> AlphabetJumpTable {
        try #require(AlphabetJumpTable(mhod: IndexFixture.jumpTable(
            criterion: 4, entries: [(65, 0, 3), (66, 3, 2)])))
    }

    @Test("adjacent runs of the same letter are joined")
    func mergesAdjacentRuns() throws {
        let rebuilt = try table().rebuilt(fromRuns: [(65, 2), (65, 1), (66, 2), (0x30, 4), (0, 1)])
        #expect(rebuilt.entries.map { ($0.letter, $0.start, $0.count) }.map { [$0.0, $0.1, $0.2] }
                == [[65, 0, 3], [66, 3, 2], [0x30, 5, 4], [0, 9, 1]])
        #expect(rebuilt.lettersAreContiguous)
    }

    @Test("a letter in two places gives two entries and loses contiguity")
    func repeatedLetterBreaksContiguity() throws {
        let rebuilt = try table().rebuilt(fromRuns: [(85, 9), (65, 3), (85, 2)])
        #expect(rebuilt.entries.count == 3)
        #expect(!rebuilt.lettersAreContiguous)
        #expect(rebuilt.entries[2].start == 12)
    }

    @Test("empty runs are skipped")
    func skipsEmptyRuns() throws {
        let rebuilt = try table().rebuilt(fromRuns: [(65, 0), (66, 2)])
        #expect(rebuilt.entries.count == 1)
        #expect(rebuilt.entries[0].letter == 66)
        #expect(rebuilt.entries[0].start == 0)
    }

    @Test("a flattened bar is one entry without a letter")
    func flattened() throws {
        let flat = try table().flattened(total: 1603)
        #expect(flat.entries.count == 1)
        #expect(flat.entries[0].letter == AlphabetJumpTable.empty)
        #expect(flat.entries[0].count == 1603)
        // The header the same except for the length, which must match one entry.
        let header = flat.mhod().rawHeader
        #expect(Array(header[0..<8]) == Array((try table()).mhod().rawHeader[0..<8]))
        #expect(flat.mhod().byteCount == 24 + AlphabetJumpTable.preambleLength + AlphabetJumpTable.entryLength)
    }

    @Test("letter codes follow the iTunes rules")
    func letterCodes() {
        #expect(ITLibrary.letterCode(for: "Bends") == 66)
        #expect(ITLibrary.letterCode(for: "beerbongs & bentleys") == 66)
        #expect(ITLibrary.letterCode(for: "…But Seriously") == 66)
        #expect(ITLibrary.letterCode(for: " Parking Lot - SINGLE") == 80)
        #expect(ITLibrary.letterCode(for: "808s & Heartbreak") == AlphabetJumpTable.digitsAndOther)
        #expect(ITLibrary.letterCode(for: "ダンシング・ヒーロー") == AlphabetJumpTable.digitsAndOther)
        #expect(ITLibrary.letterCode(for: "Éclat") == 69)
        #expect(ITLibrary.letterCode(for: "") == AlphabetJumpTable.empty)
        #expect(ITLibrary.letterCode(for: "…") == AlphabetJumpTable.empty)
    }
}
