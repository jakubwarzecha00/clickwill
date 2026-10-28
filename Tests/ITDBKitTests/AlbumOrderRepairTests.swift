import Foundation
import Testing
@testable import ITDBKit

@Suite("Album order repair")
struct AlbumOrderRepairTests {

    private func move(_ album: String, from: [Range<Int>], to: Range<Int>) -> AlbumOrderRepair.Move {
        AlbumOrderRepair.Move(album: album, trackCount: to.count, from: from, to: to, letter: nil)
    }

    /// A rotation in which the target of one move is the source of another. That is exactly
    /// what the damage looks like on a real device.
    @Test("overlapping ranges do not overwrite each other")
    func overlappingRangesUseOriginalSource() throws {
        // Slots 0-1 hold B, slots 2-3 hold A. We swap them.
        let entries: [UInt32] = [10, 11, 20, 21]
        let moves = [
            move("A", from: [2..<4], to: 0..<2),
            move("B", from: [0..<2], to: 2..<4),
        ]
        let result = try ITLibrary.applying(moves, to: entries, orderedBy: <)
        #expect(result == [20, 21, 10, 11])
    }

    @Test("a rotation of four ranges stays a permutation")
    func fourWayRotation() throws {
        let entries: [UInt32] = Array(0..<12).map(UInt32.init)
        let moves = [
            move("A", from: [9..<12], to: 0..<3),
            move("B", from: [0..<3], to: 3..<6),
            move("C", from: [3..<6], to: 6..<9),
            move("D", from: [6..<9], to: 9..<12),
        ]
        let result = try ITLibrary.applying(moves, to: entries, orderedBy: <)
        #expect(Set(result) == Set(entries))
        #expect(result == [9, 10, 11, 0, 1, 2, 3, 4, 5, 6, 7, 8])
    }

    @Test("a block made of two pieces is joined into one")
    func gathersSplitBlock() throws {
        // The album lies in slots 0 and 3-5, and should go as a whole to 0-3.
        let entries: [UInt32] = [99, 50, 51, 96, 97, 98]
        let moves = [
            move("split", from: [0..<1, 3..<6], to: 0..<4),
            move("other", from: [1..<3], to: 4..<6),
        ]
        let result = try ITLibrary.applying(moves, to: entries, orderedBy: <)
        #expect(result == [96, 97, 98, 99, 50, 51])
    }

    @Test("a mismatched number of slots is rejected")
    func rejectsSizeMismatch() {
        let entries: [UInt32] = [0, 1, 2, 3]
        let moves = [move("A", from: [0..<3], to: 0..<2)]
        #expect(throws: AlbumOrderRepairError.self) {
            _ = try ITLibrary.applying(moves, to: entries, orderedBy: <)
        }
    }

    @Test("a move that loses a track is rejected")
    func rejectsLostTrack() {
        let entries: [UInt32] = [0, 1, 2, 3]
        // The move copies 0-1 to 2-3, and nobody takes the freed place -
        // two tracks would appear twice, and two would be lost.
        let moves = [move("A", from: [0..<2], to: 2..<4)]
        #expect(throws: AlbumOrderRepairError.self) {
            _ = try ITLibrary.applying(moves, to: entries, orderedBy: <)
        }
    }
}
