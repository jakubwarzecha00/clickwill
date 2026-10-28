import Foundation

extension Mhod {
    /// Header length of a text record - constant across the database.
    static let textHeaderLength = 24
    /// How many payload bytes precede the characters themselves.
    static let textBodyPrefixLength = 16

    /// Builds a new text record.
    ///
    /// Layout confirmed on all 11,963 text records of the test database:
    /// header bytes 0x10-0x17 are always zeros, and in the payload the position is 1,
    /// the encoding 1 (UTF-16LE), and the next four bytes are zeros.
    public static func text(type: MhodType, value: String) -> Mhod {
        var units: [UInt8] = []
        for unit in value.utf16 {
            units.append(UInt8(unit & 0xFF))
            units.append(UInt8(unit >> 8))
        }
        let total = textHeaderLength + textBodyPrefixLength + units.count

        var header = [UInt8](repeating: 0, count: textHeaderLength)
        header.replaceSubrange(0..<4, with: Array("mhod".utf8))
        header.set(RecordLayout.headerLength, UInt32(textHeaderLength))
        header.set(RecordLayout.totalLength, UInt32(total))
        header.set(MhodLayout.type, type.rawValue)

        var body = [UInt8](repeating: 0, count: textBodyPrefixLength)
        body.set(MhodLayout.Text.position, 1)
        body.set(MhodLayout.Text.byteCount, UInt32(units.count))
        body.set(MhodLayout.Text.encoding, 1)    // UTF-16LE
        body += units

        return Mhod(type: type, text: value, rawHeader: header, rawBody: body)
    }

    /// A copy of the record with its content replaced. Keeps the original header,
    /// so that any unknown fields survive the edit.
    public func replacingText(_ value: String) -> Mhod {
        let rebuilt = Mhod.text(type: type, value: value)
        var header = rawHeader
        header.set(RecordLayout.totalLength, UInt32(header.count + rebuilt.rawBody.count))
        return Mhod(type: type, text: value, rawHeader: header, rawBody: rebuilt.rawBody)
    }
}

extension ITTrack {
    /// A copy of the track with a text field's value changed.
    /// `nil` removes the field from the record.
    ///
    /// An existing field is replaced **in place**, so as not to disturb the order
    /// of records, which iTunes keeps constant. A new field goes at the end.
    public func setting(_ type: MhodType, to value: String?) -> ITTrack {
        var copy = self
        let index = mhods.firstIndex { $0.type == type }

        switch (value, index) {
        case (let value?, let index?):
            copy.mhods[index] = mhods[index].replacingText(value)
            copy.fields[type] = value
        case (let value?, nil):
            copy.mhods.append(Mhod.text(type: type, value: value))
            copy.fields[type] = value
        case (nil, let index?):
            copy.mhods.remove(at: index)
            copy.fields[type] = nil
        case (nil, nil):
            break
        }
        return copy
    }
}

extension ITLibrary {
    /// A copy of the library with tracks passed through a transformation.
    public func mappingTracks(_ transform: (ITTrack) -> ITTrack) -> ITLibrary {
        var copy = self
        copy.sections = sections.map { section in
            guard case .tracks(let tracks) = section.content else { return section }
            var updated = section
            updated.content = .tracks(tracks.map(transform))
            return updated
        }
        return copy
    }

    /// The same for album records (`mhia`).
    public func mappingAlbums(_ transform: (ITAlbum) -> ITAlbum) -> ITLibrary {
        var copy = self
        copy.sections = sections.map { section in
            guard case .albums(let albums) = section.content else { return section }
            var updated = section
            updated.content = .albums(albums.map(transform))
            return updated
        }
        return copy
    }
}
