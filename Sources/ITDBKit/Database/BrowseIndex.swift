import Foundation

/// Browse table - an `mhod` record of type 52 in the master playlist.
///
/// It is not a sorting hint or a key. It is a **ready permutation of the whole
/// library**: the value at position `i` is the `mhit` record number (counting from zero)
/// that the device shows as the `i`-th. The database keeps one such table per
/// browse criterion and duplicates the whole set in `mhsd` sections of type 2 and 3.
public struct BrowseIndex: Sendable {
    /// The criterion by which the permutation was ordered.
    ///
    /// A struct, not an `enum`, because the test database contains criteria 35 and 36
    /// that could not be assigned to any menu - they must survive reading and writing.
    public struct Criterion: RawRepresentable, Hashable, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let title = Criterion(rawValue: 3)
        public static let album = Criterion(rawValue: 4)
        public static let artist = Criterion(rawValue: 5)
        public static let genre = Criterion(rawValue: 7)
        public static let composer = Criterion(rawValue: 18)

        public var label: String {
            switch self {
            case .title: return "titles"
            case .album: return "albums"
            case .artist: return "artists"
            case .genre: return "genres"
            case .composer: return "composers"
            default: return "criterion \(rawValue)"
            }
        }
    }

    /// How many body bytes precede the table itself. The first eight carry the criterion
    /// and the count; the remaining forty are zeros in all examined databases.
    static let preambleLength = 48

    public let criterion: Criterion
    /// Track positions in the `mhit` list, in display order.
    public var entries: [UInt32]

    private let rawHeader: [UInt8]
    private let preamble: [UInt8]

    /// Reads the table from a record. `nil` if the record is not of type 52
    /// or its body does not match the declared number of entries.
    public init?(mhod: Mhod) {
        guard mhod.type == .libraryPlaylistIndex else { return nil }
        guard mhod.rawBody.count >= Self.preambleLength else { return nil }
        let declared = Int(mhod.rawBody[MhodLayout.BrowseBody.entryCount] ?? 0)
        guard mhod.rawBody.count == Self.preambleLength + declared * 4 else { return nil }

        criterion = Criterion(rawValue: mhod.rawBody[MhodLayout.BrowseBody.criterion] ?? 0)
        preamble = Array(mhod.rawBody[0..<Self.preambleLength])
        rawHeader = mhod.rawHeader
        entries = (0..<declared).map {
            ByteWriter.value(UInt32.self, at: Self.preambleLength + $0 * 4, in: mhod.rawBody) ?? 0
        }
    }

    /// Assembles the record back. The count in the preamble comes from the table,
    /// not from the value read - so shortening the table stays consistent.
    public func mhod() -> Mhod {
        var body = preamble
        body.set(MhodLayout.BrowseBody.entryCount, UInt32(entries.count))
        for entry in entries { ByteWriter.append(entry, to: &body) }
        var header = rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + body.count))
        return Mhod(type: .libraryPlaylistIndex, text: nil, rawHeader: header, rawBody: body)
    }

    /// Checks that the table is a permutation of the range `0..<count`.
    /// Every ordering operation must preserve this condition.
    public func isPermutation(of count: Int) -> Bool {
        entries.count == count && Set(entries) == Set((0..<count).map(UInt32.init))
    }
}

/// Alphabetical jump bar - an `mhod` record of type 53.
///
/// Each entry says at which browse table position a given letter starts
/// and how many positions it spans. Scrolling through letters with the wheel uses this.
/// A permutation **within** a single letter leaves this bar valid.
public struct AlphabetJumpTable: Sendable {
    public struct Entry: Sendable {
        /// Code point of the letter. Outside the alphabet the device uses `0` and `?`.
        public var letter: UInt32
        public var start: UInt32
        public var count: UInt32

        public var character: Character? {
            guard let scalar = Unicode.Scalar(letter) else { return nil }
            return Character(scalar)
        }
        public var range: Range<Int> { Int(start)..<Int(start + count) }
    }

    static let preambleLength = 16
    static let entryLength = 12
    /// Entry: the letter's code point, first position, number of positions.
    static let letterField = HeaderField<UInt32>(0x00)
    static let startField = HeaderField<UInt32>(0x04)
    static let countField = HeaderField<UInt32>(0x08)

    public let criterion: BrowseIndex.Criterion
    public var entries: [Entry]

    private let rawHeader: [UInt8]
    private let preamble: [UInt8]

    public init?(mhod: Mhod) {
        guard mhod.type == .libraryPlaylistJumpTable else { return nil }
        guard mhod.rawBody.count >= Self.preambleLength else { return nil }
        let declared = Int(mhod.rawBody[MhodLayout.BrowseBody.entryCount] ?? 0)
        guard mhod.rawBody.count == Self.preambleLength + declared * Self.entryLength else { return nil }

        criterion = BrowseIndex.Criterion(rawValue: mhod.rawBody[MhodLayout.BrowseBody.criterion] ?? 0)
        preamble = Array(mhod.rawBody[0..<Self.preambleLength])
        rawHeader = mhod.rawHeader
        entries = (0..<declared).map { index in
            let base = Self.preambleLength + index * Self.entryLength
            func field(_ field: HeaderField<UInt32>) -> UInt32 {
                ByteWriter.value(UInt32.self, at: base + field.offset, in: mhod.rawBody) ?? 0
            }
            return Entry(letter: field(Self.letterField), start: field(Self.startField), count: field(Self.countField))
        }
    }

    public func mhod() -> Mhod {
        var body = preamble
        body.set(MhodLayout.BrowseBody.entryCount, UInt32(entries.count))
        for entry in entries {
            var chunk = [UInt8](repeating: 0, count: Self.entryLength)
            chunk.set(Self.letterField, entry.letter)
            chunk.set(Self.startField, entry.start)
            chunk.set(Self.countField, entry.count)
            body += chunk
        }
        var header = rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + body.count))
        return Mhod(type: .libraryPlaylistJumpTable, text: nil, rawHeader: header, rawBody: body)
    }

    /// The browse table range covered by the letter that starts a given position.
    public func section(containing position: Int) -> Entry? {
        entries.first { $0.range.contains(position) }
    }

    /// Codes outside the alphabet used by the device. Measured in its own
    /// bars: digits and non-Latin scripts go under `'0'`, empty
    /// values under `0` - and always at the end, in that order.
    public static let digitsAndOther: UInt32 = 0x30
    public static let empty: UInt32 = 0

    /// Whether each letter occupies one continuous run. That is what an alphabetically
    /// ordered bar looks like; with an arbitrary order letters repeat.
    public var lettersAreContiguous: Bool {
        var seen: Set<UInt32> = []
        for entry in entries {
            if !seen.insert(entry.letter).inserted { return false }
        }
        return true
    }

    /// A new bar with the same header, computed from runs (letter code, length)
    /// in order of appearance. Adjacent runs with the same code are merged.
    public func rebuilt(fromRuns runs: [(letter: UInt32, count: Int)]) -> AlphabetJumpTable {
        var copy = self
        var result: [Entry] = []
        var position = 0
        for run in runs where run.count > 0 {
            if let last = result.last, last.letter == run.letter {
                result[result.count - 1].count += UInt32(run.count)
            } else {
                result.append(Entry(letter: run.letter, start: UInt32(position), count: UInt32(run.count)))
            }
            position += run.count
        }
        copy.entries = result
        return copy
    }

    /// A bar without letters: one entry covering everything. The format the device
    /// writes itself for criteria with empty values.
    public func flattened(total: Int) -> AlphabetJumpTable {
        rebuilt(fromRuns: [(Self.empty, total)])
    }
}
