import Foundation

/// Where each record of an iTunesDB lies, read only from the record headers - so it works on
/// a database the parser doesn't understand. For the diagnostic report: the shape of a
/// library from an unknown model, and which record and field a byte that didn't rebuild
/// belongs to. Text is never copied out: an `mhod` body is named, its bytes are not.
///
/// Every record starts with a four-letter tag and its header length. A list (`mhl*`) gives
/// the number of children at 0x08 and they follow its header; any other record gives its
/// total length at 0x08 and its children fill the space after the header.
public struct RecordMap: Sendable {

    public struct Record: Sendable {
        public let tag: String
        public let offset: Int
        public let headerLength: Int
        public let end: Int
        /// `mhsd` and `mhod` type (0x0C); `nil` for the other records.
        public let type: Int?
        /// Position among the siblings with the same tag, from 0.
        public let index: Int
        public let depth: Int
        public let parent: Int?
    }

    public let records: [Record]
    /// Bytes no record covered - after the last one, or where a length led nowhere.
    public let uncovered: Int

    public static func build(_ data: Data) -> RecordMap {
        let bytes = [UInt8](data)
        var records: [Record] = []

        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        func tag(_ at: Int) -> String? {
            guard at + 4 <= bytes.count else { return nil }
            let text = String(decoding: bytes[at..<(at + 4)], as: UTF8.self)
            return text.hasPrefix("mh") && text.allSatisfy(\.isLetter) ? text : nil
        }

        /// Reads the record at `offset` and its children; returns where it ends.
        @discardableResult
        func walk(_ offset: Int, limit: Int, depth: Int, parent: Int?, index: Int) -> Int? {
            guard depth < 16, let name = tag(offset), let header = u32(offset + 4), header >= 12,
                  offset + header <= limit, let field = u32(offset + 8) else { return nil }
            let slot = records.count
            let isList = name.hasPrefix("mhl")
            let type = name == "mhsd" || name == "mhod" ? u32(offset + 12) : nil
            records.append(Record(tag: name, offset: offset, headerLength: header, end: offset + header,
                                  type: type, index: index, depth: depth, parent: parent))
            var end: Int
            var counts: [String: Int] = [:]
            func child(at position: Int, within bound: Int) -> Int? {
                guard let childTag = tag(position) else { return nil }
                let next = walk(position, limit: bound, depth: depth + 1, parent: slot, index: counts[childTag, default: 0])
                counts[childTag, default: 0] += 1
                return next
            }
            if isList {
                end = offset + header
                for _ in 0..<min(field, 1_000_000) {
                    guard let next = child(at: end, within: limit) else { break }
                    end = next
                }
            } else {
                end = min(offset + max(field, header), limit)
                // An `mhod` holds data, not records.
                if name != "mhod" {
                    var position = offset + header
                    while position < end, let next = child(at: position, within: end), next > position { position = next }
                }
            }
            records[slot] = Record(tag: name, offset: offset, headerLength: header, end: end,
                                   type: type, index: index, depth: depth, parent: parent)
            return end
        }

        let end = walk(0, limit: bytes.count, depth: 0, parent: nil, index: 0) ?? 0
        return RecordMap(records: records, uncovered: bytes.count - end)
    }

    /// The deepest record holding `offset`.
    public func record(at offset: Int) -> Record? {
        records.last { $0.offset <= offset && offset < $0.end }
    }

    /// `mhbd > mhsd[type 1] > mhlt > mhit #12 > mhod[type 2]`.
    public func path(of record: Record) -> String {
        var chain: [Record] = [record]
        while let parent = chain.last?.parent { chain.append(records[parent]) }
        return chain.reversed().map { record in
            switch record.tag {
            case "mhbd", "mhlt", "mhlp", "mhla": record.tag
            case "mhsd", "mhod": "\(record.tag)[type \(record.type.map(String.init) ?? "?")]"
            default: "\(record.tag) #\(record.index)"
            }
        }.joined(separator: " > ")
    }

    /// Like `path`, with the position at every level - siblings of one tag stay apart.
    func key(of record: Record) -> String {
        var chain: [Record] = [record]
        while let parent = chain.last?.parent { chain.append(records[parent]) }
        return chain.reversed().map { "\($0.tag)#\($0.index)" }.joined(separator: ">")
    }

    /// Where a byte lies, for the report: the record, the offset inside it and whether it is
    /// in the header or the body. Bytes of an `mhod` body are text and are never shown.
    public struct Location: Sendable {
        public let path: String
        public let offsetInRecord: Int
        public let inHeader: Bool
        public let isText: Bool
    }

    public func locate(_ offset: Int) -> Location? {
        guard let record = record(at: offset) else { return nil }
        let inside = offset - record.offset
        return Location(path: path(of: record), offsetInRecord: inside, inHeader: inside < record.headerLength,
                        isText: record.tag == "mhod" && inside >= record.headerLength)
    }

    /// A record whose length differs in another map of the same database.
    public struct LengthChange: Sendable {
        public let record: Record
        public let rebuiltLength: Int
        /// `mhod 5 → 4` when the number of children changed.
        public let children: String?
    }

    /// Records whose length differs in `other`, split into the deepest ones (`causes`: none of
    /// their children changed length) and the ones that only contain them. Records are paired
    /// by path, so a record dropped from the middle of a list shifts only its later siblings.
    public func lengthChanges(comparedWith other: RecordMap) -> (causes: [LengthChange], ancestors: [Record]) {
        let theirs = Dictionary(other.records.map { (other.key(of: $0), $0) }, uniquingKeysWith: { a, _ in a })
        func children(_ map: RecordMap, _ index: Int) -> [Record] { map.records.filter { $0.parent == index } }
        var changed: [(index: Int, change: LengthChange)] = []
        for (index, record) in records.enumerated() {
            guard let match = theirs[key(of: record)] else { continue }
            let length = record.end - record.offset, rebuilt = match.end - match.offset
            guard length != rebuilt else { continue }
            let mine = children(self, index)
            let matchIndex = other.records.firstIndex { $0.offset == match.offset && $0.tag == match.tag }
            let counted = matchIndex.map { children(other, $0) } ?? []
            var summary: String?
            if mine.count != counted.count {
                let tags = Set(mine.map(\.tag)).union(counted.map(\.tag)).sorted()
                summary = tags.map { tag in "\(tag) \(mine.filter { $0.tag == tag }.count) → \(counted.filter { $0.tag == tag }.count)" }
                    .joined(separator: ", ")
            }
            changed.append((index, LengthChange(record: record, rebuiltLength: rebuilt, children: summary)))
        }
        let parents = Set(changed.compactMap { records[$0.index].parent })
        return (changed.filter { !parents.contains($0.index) }.map(\.change),
                changed.filter { parents.contains($0.index) }.map(\.change.record))
    }

    /// The shape of the library: for every tag its header lengths and how many there are,
    /// in the order the tags first appear. `mhsd 96 ×5 (types 1,2,3,4,5)`.
    public var skeleton: String {
        var order: [String] = []
        var headers: [String: Set<Int>] = [:]
        var counts: [String: Int] = [:]
        var types: [String: Set<Int>] = [:]
        for record in records {
            if counts[record.tag] == nil { order.append(record.tag) }
            counts[record.tag, default: 0] += 1
            headers[record.tag, default: []].insert(record.headerLength)
            if let type = record.type { types[record.tag, default: []].insert(type) }
        }
        let parts = order.map { tag in
            let lengths = headers[tag, default: []].sorted().map(String.init).joined(separator: "/")
            let kinds = types[tag].map { " (types \($0.sorted().map(String.init).joined(separator: ",")))" } ?? ""
            return "\(tag) \(lengths) ×\(counts[tag, default: 0])\(kinds)"
        }
        return parts.joined(separator: " · ") + (uncovered > 0 ? " · \(uncovered) B outside any record" : "")
    }
}

extension Data {
    /// `01 00 2a ff` - bytes apart, so nothing in the report reads as a 16-digit identifier.
    func spacedHex(_ range: Range<Int>) -> String {
        let clamped = range.clamped(to: 0..<count)
        return self[clamped.lowerBound + startIndex..<clamped.upperBound + startIndex]
            .map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
