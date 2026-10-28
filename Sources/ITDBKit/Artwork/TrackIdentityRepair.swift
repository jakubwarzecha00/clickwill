import Foundation

/// Two identity repairs, both measured on a Classic 7G and both
/// showing the same way: the album shows artwork in Cover Flow,
/// but not for the song playing.
///
/// The symptom is the same, but there are two separate causes.

extension ITTrack {
    /// Second copy of the track identifier (`MhitLayout.secondaryPersistentID`).
    public var secondaryPersistentID: UInt64 { rawHeader[MhitLayout.secondaryPersistentID] ?? 0 }

    /// Restores the second copy of the identifier when it is missing.
    ///
    /// Measured: 1598 of 1623 tracks have their own `persistentID` at 0xA8.
    /// Exactly 25 had zero - twelve from "Ok Computer" and thirteen
    /// from "Pablo Honey", i.e. **only the albums that do not show
    /// artwork for the song**. Apple Music wrote them that way; we never
    /// zeroed this field.
    public func restoringSecondaryPersistentID() -> ITTrack {
        guard secondaryPersistentID == 0, persistentID != 0 else { return self }
        var copy = self
        guard copy.rawHeader.set(MhitLayout.secondaryPersistentID, persistentID) else { return self }
        return copy
    }
}

extension ITLibrary {
    /// Whether the device keeps a second copy of the identifier at 0xA8 at all.
    /// Classic: 1598 of 1623 tracks. Finder on the nano 2G: zero in every one
    /// (measured) - there zero is the norm, not a defect.
    public var usesSecondaryPersistentID: Bool {
        tracks.contains { $0.secondaryPersistentID != 0 }
    }

    /// Tracks without the second copy of the identifier.
    public func repairingSecondaryIdentifiers() -> (library: ITLibrary, repaired: [String: Int]) {
        guard usesSecondaryPersistentID else { return (self, [:]) }
        var repaired: [String: Int] = [:]
        let updated = mappingTracks { track in
            guard track.secondaryPersistentID == 0, track.persistentID != 0 else { return track }
            repaired[track.album ?? "", default: 0] += 1
            return track.restoringSecondaryPersistentID()
        }
        return (updated, repaired)
    }

    /// Album records that carry a track identifier.
    ///
    /// The generator took the album record identifier from the same source as the
    /// track identifier, and the caller passed a constant generator - so a new
    /// album got the identifier of its first track. A collision of
    /// two namespaces that are separate on the device: 116 of 118
    /// album records have upper 32 bits of 0x2 or 0x102, tracks have full
    /// random 64 bits.
    ///
    /// The change is safe, because a track points to its album by **number**
    /// (0x120), not by identifier; nothing in the database refers to the
    /// album record identifier.
    public func repairingAlbumIdentities(
        random: @Sendable () -> UInt32 = { UInt32.random(in: 1...UInt32.max) }
    ) -> (library: ITLibrary, repaired: [String]) {
        let trackIDs = Set(tracks.map(\.persistentID))
        let suspect = albums.filter { trackIDs.contains($0.persistentID) || !Self.isAlbumIdentity($0.persistentID) }
        guard !suspect.isEmpty else { return (self, []) }

        var used = Set(albums.map(\.persistentID)).union(trackIDs)
        var replacement: [UInt64: UInt64] = [:]
        for album in suspect {
            // Incrementing, not re-randomizing: the generator may be constant
            // (it is in tests), and then a randomizing loop would never exit.
            var fresh = Self.albumIdentitySpace | UInt64(random())
            while used.contains(fresh) { fresh &+= 1 }
            used.insert(fresh)
            replacement[album.persistentID] = fresh
        }

        var copy = self
        copy.sections = sections.map { section in
            guard case .albums(let list) = section.content else { return section }
            var changed = section
            changed.content = .albums(list.map { album in
                guard let fresh = replacement[album.persistentID] else { return album }
                var updated = album
                updated.persistentID = fresh
                return updated
            })
            return changed
        }
        return (copy, suspect.map { $0.title ?? "" })
    }
}
