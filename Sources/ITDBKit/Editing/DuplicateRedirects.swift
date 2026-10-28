import Foundation

/// Redirects needed when merging duplicates: before a removed track disappears,
/// everything that points to it must point to the copy that stays.
/// `removingTracks` alone would throw those pointers out together with the track.
extension ITLibrary {

    /// Items of regular playlists moved from the removed track (`uniqueID`) to
    /// the kept one. A playlist that already has the kept copy does not get it
    /// a second time - the removed item simply disappears. The master playlist stays
    /// unchanged: its items and browse tables are handled by `removingTracks`.
    public func redirectingPlaylistEntries(_ redirects: [UInt32: UInt32]) -> ITLibrary {
        guard !redirects.isEmpty else { return self }
        var copy = self
        copy.sections = sections.map { section in
            guard case .playlists(let playlists) = section.content else { return section }
            var updated = section
            updated.content = .playlists(playlists.map { playlist in
                guard !playlist.isMaster else { return playlist }
                var present = Set(playlist.entries.map(\.trackID))
                var rebuilt = playlist
                rebuilt.entries = playlist.entries.compactMap { entry in
                    guard let target = redirects[entry.trackID] else { return entry }
                    guard !present.contains(target) else { return nil }
                    present.insert(target)
                    var moved = entry
                    moved.trackID = target
                    return moved
                }
                return rebuilt
            })
            return updated
        }
        return copy
    }

    /// The artwork pointer in the album record (`mhia` 0x20) moved from the removed
    /// track (`persistentID`) to the kept one.
    public func redirectingAlbumArtworkOwners(_ owners: [UInt64: UInt64]) -> ITLibrary {
        guard !owners.isEmpty else { return self }
        var copy = self
        copy.sections = sections.map { section in
            guard case .albums(let albums) = section.content else { return section }
            var updated = section
            updated.content = .albums(albums.map { album in
                guard let owner = owners[album.artworkOwnerPersistentID] else { return album }
                var changed = album
                changed.artworkOwnerPersistentID = owner
                return changed
            })
            return updated
        }
        return copy
    }
}

extension ArtworkLibrary {

    /// The same `ArtworkDB` content with image owners moved the way
    /// `ArtworkDBEditor.settingOwners` will do it on write - so that the preview
    /// in the app does not lose the album artwork before the write.
    public func reowning(_ owners: [UInt64: UInt64]) -> ArtworkLibrary {
        guard !owners.isEmpty else { return self }
        let images = images.map { image in
            guard let owner = owners[image.trackPersistentID] else { return image }
            return ArtworkImage(id: image.id, trackPersistentID: owner, variants: image.variants, rawHeader: image.rawHeader)
        }
        return ArtworkLibrary(images: images, formats: formats, rawHeader: rawHeader, sourceByteCount: sourceByteCount)
    }
}
