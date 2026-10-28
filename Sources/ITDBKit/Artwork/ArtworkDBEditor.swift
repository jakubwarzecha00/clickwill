import Foundation

/// Adds an image to `ArtworkDB` at the byte level: copies an existing `mhii`
/// record (with its `mhod`/`mhni`/`mhaf` children) as a template, replaces
/// only the fields that must differ, and inserts it at the end of the `mhli` list.
/// The rest of the file stays byte for byte - no reserialization, so there is
/// nothing to break apart from four counters and one identifier.
///
/// Fields are in `ArtworkLayout.swift`. From the template we replace the owner, the
/// source size, the track count and the variant offsets; dimensions and file names from
/// the template are correct, because the formats are fixed per device. The album points
/// to its artwork in `iTunesDB` (`MhiaLayout.artworkOwner`, `ITLibrary.linkingAlbumArtwork`).
public enum ArtworkDBEditor {

    public struct NewImage: Sendable {
        public var trackPersistentID: UInt64
        public var sourceByteCount: UInt32
        public var trackCount: UInt32
        /// Offset of the new slot in each format's file (correlationID -> offset).
        public var slotOffsets: [UInt32: UInt32]

        public init(trackPersistentID: UInt64, sourceByteCount: UInt32, trackCount: UInt32, slotOffsets: [UInt32: UInt32]) {
            self.trackPersistentID = trackPersistentID
            self.sourceByteCount = sourceByteCount
            self.trackCount = trackCount
            self.slotOffsets = slotOffsets
        }
    }

    public struct Result: Sendable {
        public let data: Data
        public let imageID: UInt32
    }

    /// Inserts a new image built on the `templateImageID` template (any
    /// existing one; if not given - the first in the list).
    public static func addingImage(to data: Data, template templateImageID: UInt32? = nil, image: NewImage) throws -> Result {
        let bytes = [UInt8](data)
        let list = try imageList(in: data)
        guard let templateRange = list.records.first(where: { range in
            templateImageID == nil || Array(bytes[range])[MhiiLayout.imageID] == templateImageID
        }) else { throw ITDBError.writeRefused(.inconsistent("no template mhii")) }

        // Copy of the template with the fields replaced.
        var record = Array(bytes[templateRange])
        record.set(MhiiLayout.ownerPersistentID, image.trackPersistentID)
        record.set(MhiiLayout.sourceByteCount, image.sourceByteCount)
        record.set(MhiiLayout.trackCount, image.trackCount)
        let reader = ByteReader(record)
        var child = Int(try reader.value(RecordLayout.headerLength, inRecordAt: 0))
        var patched: Set<UInt32> = []
        for _ in 0..<Int(try reader.value(MhiiLayout.childCount, inRecordAt: 0)) {
            let childTotal = Int(try reader.value(RecordLayout.totalLength, inRecordAt: child))
            if try reader.value(ArtworkMhodLayout.type, inRecordAt: child) == ArtworkMhodLayout.variantContainer {
                let mhni = child + Int(try reader.value(RecordLayout.headerLength, inRecordAt: child))
                let correlation = try reader.value(MhniLayout.formatID, inRecordAt: mhni)
                guard let slot = image.slotOffsets[correlation] else {
                    throw ITDBError.writeRefused(.inconsistent("no offset for format \(correlation)"))
                }
                ByteWriter.put(slot, at: mhni + MhniLayout.byteOffset.offset, in: &record)
                patched.insert(correlation)
            }
            child += childTotal
        }
        guard patched == Set(image.slotOffsets.keys) else {
            throw ITDBError.writeRefused(.inconsistent("template formats \(patched.sorted()) != given \(image.slotOffsets.keys.sorted())"))
        }
        return try insertingImage(record, into: data)
    }

    /// Appends a ready `mhii` record at the end of the image list. The identifier
    /// comes from the file counter (`MhfdLayout.nextImageID`); fixes four
    /// counters and nothing else.
    public static func insertingImage(_ record: [UInt8], into data: Data) throws -> Result {
        // At least the start of the header with the length and the identifier.
        guard record.count >= 0x18, String(decoding: record[0..<4], as: UTF8.self) == "mhii",
              record[RecordLayout.totalLength].map(Int.init) == record.count
        else { throw ITDBError.writeRefused(.inconsistent("the image record isn't a complete mhii")) }
        let list = try imageList(in: data)
        var bytes = [UInt8](data)
        guard let nextID = bytes[MhfdLayout.nextImageID],
              let sectionTotal = ByteWriter.value(UInt32.self, at: list.sectionStart + RecordLayout.totalLength.offset, in: bytes),
              let fileTotal = bytes[RecordLayout.totalLength]
        else { throw ITDBError.writeRefused(.inconsistent("the ArtworkDB header is too short")) }
        var record = record
        record.set(MhiiLayout.imageID, nextID)

        bytes.insert(contentsOf: record, at: list.sectionEnd)
        let added = UInt32(record.count)
        ByteWriter.put(UInt32(list.records.count + 1), at: list.listStart + RecordLayout.listChildCount.offset, in: &bytes)
        ByteWriter.put(sectionTotal + added, at: list.sectionStart + RecordLayout.totalLength.offset, in: &bytes)
        bytes.set(RecordLayout.totalLength, fileTotal + added)
        bytes.set(MhfdLayout.nextImageID, nextID + 1)
        return Result(data: Data(bytes), imageID: nextID)
    }

    /// The image section and the ranges of its `mhii` records. Throws when the list
    /// does not end exactly where the section does - inserting at the end of the list
    /// would then assume something the file does not say.
    private static func imageList(in data: Data) throws -> ImageList {
        guard let list = try walkImageList(data) else { throw ITDBError.writeRefused(.inconsistent("ArtworkDB has no image section")) }
        let cursor = list.records.last?.upperBound ?? list.firstRecord
        guard cursor == list.sectionEnd else {
            throw ITDBError.writeRefused(.inconsistent("the mhii list ends at \(cursor), the section at \(list.sectionEnd)"))
        }
        return list
    }

    struct ImageList {
        let sectionStart: Int
        let listStart: Int
        let sectionEnd: Int
        /// Where the first record starts (after the list header).
        let firstRecord: Int
        let records: [Range<Int>]
    }

    /// Walk of the image section (`mhsd` of type 1) and its `mhli` list - the only
    /// place that knows it. `nil` for a file without such a section.
    private static func walkImageList(_ data: Data) throws -> ImageList? {
        let reader = ByteReader(data)
        guard try reader.signature(at: 0) == "mhfd" else {
            throw ITDBError.unexpectedSignature(expected: "mhfd", found: try reader.signature(at: 0), offset: 0)
        }
        var offset = Int(try reader.value(RecordLayout.headerLength, inRecordAt: 0))
        for _ in 0..<Int(try reader.value(MhfdLayout.sectionCount, inRecordAt: 0)) {
            let total = Int(try reader.value(RecordLayout.totalLength, inRecordAt: offset))
            guard try reader.value(ArtworkSectionLayout.type, inRecordAt: offset) == ArtworkSectionLayout.images else {
                offset += total
                continue
            }
            let listStart = offset + Int(try reader.value(RecordLayout.headerLength, inRecordAt: offset))
            guard try reader.signature(at: listStart) == "mhli" else {
                throw ITDBError.unexpectedSignature(expected: "mhli", found: try reader.signature(at: listStart), offset: listStart)
            }
            let first = listStart + Int(try reader.value(RecordLayout.headerLength, inRecordAt: listStart))
            var cursor = first
            var records: [Range<Int>] = []
            for _ in 0..<Int(try reader.value(RecordLayout.listChildCount, inRecordAt: listStart)) {
                guard try reader.signature(at: cursor) == "mhii" else {
                    throw ITDBError.unexpectedSignature(expected: "mhii", found: try reader.signature(at: cursor), offset: cursor)
                }
                let length = Int(try reader.value(RecordLayout.totalLength, inRecordAt: cursor))
                records.append(cursor..<(cursor + length))
                cursor += length
            }
            return ImageList(sectionStart: offset, listStart: listStart, sectionEnd: offset + total,
                             firstRecord: first, records: records)
        }
        return nil
    }

    /// How many tracks of the album use a given image (`MhiiLayout.trackCount`).
    ///
    /// Measured on the device: the sums of this value over one album's images
    /// match its track count (DOPAMINE 15+1 = 16, I AM MUSIC
    /// 26+1+1+1 = 29). An album whose only image declares 1 track out of 13
    /// shows no artwork on the iPod, even though the app sees it - because the app
    /// only asks whether **any** track has an image.
    public static func trackCounts(in data: Data) throws -> [(imageID: UInt32, ownerPersistentID: UInt64, trackCount: UInt32)] {
        try withImageRecords(data) { bytes, range in
            let record = Array(bytes[range])
            return (record[MhiiLayout.imageID] ?? 0, record[MhiiLayout.ownerPersistentID] ?? 0, record[MhiiLayout.trackCount] ?? 0)
        }
    }

    /// Replaces `MhiiLayout.trackCount` in the given records. Everything except that one word
    /// per record stays byte for byte - lengths do not change, so there are
    /// no counters to recalculate.
    public static func settingTrackCounts(_ counts: [UInt32: UInt32], in data: Data) throws -> Data {
        var bytes = [UInt8](data)
        let ranges: [Range<Int>] = try withImageRecords(data) { _, range in range }
        for range in ranges {
            guard let id = Array(bytes[range])[MhiiLayout.imageID], let value = counts[id] else { continue }
            ByteWriter.put(value, at: range.lowerBound + MhiiLayout.trackCount.offset, in: &bytes)
        }
        return Data(bytes)
    }

    /// Moves the image owner (`MhiiLayout.ownerPersistentID`) from a track that goes away
    /// to the one that replaces it. Cover Flow finds album artwork through the owner,
    /// so removing it without moving it would leave the album without artwork in Cover Flow.
    /// As with the track count: one field per record, lengths unchanged.
    public static func settingOwners(_ owners: [UInt64: UInt64], in data: Data) throws -> (data: Data, changed: Int) {
        var bytes = [UInt8](data)
        let ranges: [Range<Int>] = try withImageRecords(data) { _, range in range }
        var changed = 0
        for range in ranges {
            guard let owner = Array(bytes[range])[MhiiLayout.ownerPersistentID], let replacement = owners[owner] else { continue }
            ByteWriter.put(replacement, at: range.lowerBound + MhiiLayout.ownerPersistentID.offset, in: &bytes)
            changed += 1
        }
        return (Data(bytes), changed)
    }

    /// Every `mhii` record in turn - shared by reading and writing record fields.
    static func withImageRecords<T>(_ data: Data, _ body: ([UInt8], Range<Int>) throws -> T) throws -> [T] {
        guard let list = try walkImageList(data) else { throw ITDBError.writeRefused(.inconsistent("ArtworkDB has no image list")) }
        let bytes = [UInt8](data)
        return try list.records.map { try body(bytes, $0) }
    }
}
