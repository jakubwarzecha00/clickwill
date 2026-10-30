import Foundation
import ITDBKit
import ClickwillModel

/// The one place that turns an error into a sentence for the user.
///
/// Errors of the core and the model carry cases and data; their `description` is a technical
/// description for `ipodctl` and the diagnostic report. The sentence the app user
/// sees is created here - an exhaustive `switch` over every type,
/// so a new case cannot get through without its own sentence.
enum ErrorPresenter {

    static func message(for error: any Error) -> String {
        // System errors (files, network, volumes) arrive as NSError - their
        // text is "Error Domain=... Code=...", and the sentence is in localizedDescription.
        if type(of: error) is NSError.Type { return error.localizedDescription }
        switch error {
        case let error as ITDBError: return message(for: error)
        case let error as FileImportError: return message(for: error)
        case let error as ArtworkError: return message(for: error)
        case let error as SyncedTracksRefusal: return message(for: error)
        case let error as ConversionQueueError: return message(for: error)
        case let error as MetadataError: return message(for: error)
        case let error as AudioConversionError: return message(for: error)
        case let error as AudioImport.ImportError: return message(for: error)
        case let error as BackupRestoreError: return message(for: error)
        case let error as WriteBlocked: return message(for: error)
        case let error as FeedbackSubmission.Failure: return message(for: error)
        case let error as AudioCD.ReadError: return message(for: error)
        case let error as MusicBrainz.LookupError: return message(for: error)
        default: return String(describing: error)
        }
    }

    // MARK: - Core errors

    static func message(for error: ITDBError) -> String {
        switch error {
        case .noIPodFound:
            "No iPod found. Check that it's connected and shows up in Finder."
        case .notAnITunesDB:
            "This file isn't an iPod library."
        case .databaseTooSmall(let bytes, let needed):
            "The iPod's library file is too short to read (\(bytes) of at least \(needed) bytes)."
        case .invalidFireWireID(let value):
            "A FireWire GUID has exactly 16 characters, 0 to 9 and A to F. \u{201C}\(value)\u{201D} doesn't."
        case .fireWireIDUnavailable(let volume):
            "Clickwill couldn't read the FireWire GUID of \u{201C}\(volume)\u{201D}, which it needs to sign this iPod's library. The iPod stays read-only."
        case .unsupportedHashingScheme(let scheme):
            "This iPod signs its library in a way Clickwill doesn't support yet (scheme \(scheme)). It opens read-only."
        case .signatureMismatch(let stored, let computed):
            "The library's signature doesn't match, so Clickwill won't write to it.\n  stored    \(stored)\n  computed  \(computed)"
        case .snapshotNotFound:
            "This backup is no longer on this Mac."
        case .snapshotCorrupted(_, let file):
            "This backup is damaged (\(file) doesn't match what was saved), so it can't be restored. Choose another backup."
        case .snapshotIncomplete(let missing):
            "The backup couldn't be finished because \(missing) was missing. The incomplete backup was removed. Try again."
        case .pathMissing(let url):
            "Clickwill can't find \(url.lastPathComponent)."
        case .readOutOfBounds(let offset, let size):
            "The iPod's library file ends too early (\(size) bytes at \(offset)). It may be damaged."
        case .unexpectedSignature(let expected, let found, let offset):
            "The iPod's library file looks damaged (\(expected) expected at \(offset), found \(found))."
        case .lengthMismatch(let declared, let actual):
            "The iPod's library file looks damaged (\(declared) bytes expected, \(actual) found)."
        case .writeRefused(let refusal):
            // An internal condition the user can do nothing about - we ask for a report.
            if case .inconsistent = refusal {
                "Clickwill didn't write: \(reason(refusal)) Choose Send Feedback so I can look into it."
            } else {
                "Clickwill didn't write: \(reason(refusal))"
            }
        case .writeVerificationFailed(let detail):
            "The new library didn't pass its check, so nothing was written and the iPod is unchanged. \(detail)"
        case .unsafePath:
            "A file location in the iPod's library points outside the iPod, so Clickwill left that file alone."
        }
    }

    /// The rest of the sentence "Clickwill didn't write: …".
    private static func reason(_ refusal: WriteRefusal) -> String {
        switch refusal {
        case .readOnly(let reason):
            reason.map(readOnlyFact) ?? "this iPod can't be written to."
        case .preflight(let issue):
            message(for: issue)
        case .databaseChanged:
            "the library on the iPod changed since it was loaded (Apple Music may have rewritten it). Load it again and redo the changes."
        case .deviceGone:
            "the iPod disappeared. It was disconnected or mounted again."
        case .deviceSwapped:
            "a different volume now uses the iPod's name, so nothing was written to it."
        case .anotherWriter:
            "another process (Clickwill or ipodctl) is writing to this iPod. Wait until it finishes."
        case .notEnoughSpace(let needed, let available, .iPod(let reserve)):
            "there isn't enough space on the iPod. The files need \(bytes(needed - reserve)), and Clickwill always leaves \(bytes(reserve)) free; only \(bytes(available)) is free now."
        case .notEnoughSpace(let needed, let available, .originalsFolder):
            "there isn't enough space for the original files on this Mac: \(bytes(needed)) needed, \(bytes(available)) free."
        case .originalsFolderUnusable(let folder):
            "the folder for the original files, \(folder.lastPathComponent), can't be written to."
        case .emptySourceFile:
            "the audio file is empty."
        case .unsupportedArtwork(let detail):
            "this iPod wants covers in a format Clickwill doesn't write yet (\(detail))."
        case .unmergedPlayCounts(let detail):
            "the iPod holds plays that can't be merged safely (\(detail))."
        case .cannotSign(let refusal):
            "the library can't be signed: \(signing(refusal))"
        case .databaseNotReproduced(let detail):
            "experimental iPod: the library no longer rebuilds byte for byte (\(detail)). Run Diagnostics again."
        case .inconsistent(let detail):
            "an internal check failed (\(detail))."
        }
    }

    private static func signing(_ refusal: SigningRefusal) -> String {
        switch refusal {
        case .fireWireIDMissing:
            "hash58 needs the FireWire GUID, which isn't known"
        case .unsignedNotConfirmed:
            "This database carries no signature, as on iPods from before 2007 and the first two iPod nano generations. "
                + "Clickwill writes it only when the iPod confirms its model over USB and in its firmware, "
                + "and so far only for the iPod nano (2nd generation)."
        case .unknownScheme(let scheme):
            unknownScheme(scheme)
        }
    }

    private static func unknownScheme(_ scheme: UInt16) -> String {
        "This database uses signature scheme \(scheme)\(DatabaseFormat.schemeLabel(scheme).map { " (\($0))" } ?? ""), "
            + "which Clickwill can't produce yet. Only scheme 1 (hash58) has been confirmed."
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// A condition before the write - the bar at the bottom, the change list, Overview, Backups.
    static func message(for issue: WritePreflight.Issue) -> String {
        switch issue {
        case .volumeUnavailable:
            "The iPod isn't available. Check that it's connected and shows up in Finder."
        case .musicRunning:
            "Music is open. Quit Music to write to the iPod, or it will reset the order you set."
        case .pendingPlayCounts(let tracks):
            "\(tracks) songs on the iPod have new plays that Clickwill brings in before it writes."
        }
    }

    /// What is known about the device that means it cannot be written to.
    private static func readOnlyFact(_ reason: ReadOnlyReason) -> String {
        switch reason {
        case .volumeReadOnly:
            "macOS shows this iPod as read-only, so Clickwill can only browse it."
        case .identityConflict(.usbScheme(let family, let expected, let database)):
            "The iPod identifies itself as \(family), which uses signature scheme \(expected), "
                + "but its database carries scheme \(database). Clickwill will not write until the two agree."
        case .identityConflict(.firmwareGUID(let stated, let used)):
            "The iPod's firmware reports FireWire GUID \(stated), but the key found elsewhere is \(used). "
                + "Clickwill won't sign a database with a key the device doesn't confirm."
        case .fireWireIDRejected(let rejected):
            "\(guidSource(rejected.source)) gives FireWire GUID \(rejected.hex), but this iPod's library isn't signed with it. "
                + "The file may come from another iPod, so this one opens read-only."
        case .fireWireIDMissing:
            "Clickwill couldn't find this iPod's FireWire GUID, which it needs to sign the library, so the iPod opens read-only."
        case .unsignedRefused(.usbNotConfirmed):
            "This database carries no signature. Clickwill writes such a database only when the iPod "
                + "itself confirms over USB that its model uses none, and it did not."
        case .unsignedRefused(.familyNotConfirmed):
            "This database carries no signature. Writing it has been confirmed on the iPod nano "
                + "(2nd generation) only, and this iPod's firmware doesn't report that model."
        case .unsupportedScheme(let scheme):
            unknownScheme(scheme)
        }
    }

    private static func guidSource(_ source: FireWireGUID.Source) -> String {
        switch source {
        case .ioRegistry: "The iPod's USB serial number"
        case .sysInfoExtended: "Device/SysInfoExtended"
        case .sysInfo: "Device/SysInfo"
        }
    }

    // MARK: - Model errors

    static func message(for error: FileImportError) -> String {
        switch error {
        case .unreadable(let url):
            "\(url.lastPathComponent) isn't an audio file Clickwill can read. Choose an MP3, AAC, Apple Lossless, WAV, AIFF or FLAC file."
        case .rejected(let url, let reason): "\(url.lastPathComponent): \(reason)"
        case .notMissing(let title): "\u{201C}\(title)\u{201D} already has a file on the iPod."
        case .sameFile(let title): "That is the file \u{201C}\(title)\u{201D} already uses on the iPod."
        case .currentFileUnknown(let title):
            "Clickwill can't see the current file of \u{201C}\(title)\u{201D}, so it can't replace it safely. Connect the iPod itself rather than a snapshot."
        }
    }

    static func message(for error: ArtworkError) -> String {
        switch error {
        case .noExistingArtwork(let album):
            "Can't add a cover to \u{201C}\(album)\u{201D} yet: this iPod has no covers at all. Add one album with a cover using Music, then try again."
        case .unreadableImage(let url): "Couldn't read an image from \(url.lastPathComponent)."
        }
    }

    static func message(for error: SyncedTracksRefusal) -> String {
        switch error {
        case .removal(let songs):
            "This iPod rebuilds its library from its Music folder every time it starts or leaves a Mac, so \(songs == 1 ? "this song" : "\(songs) of these songs") would come back. Delete \(songs == 1 ? "its file" : "their files") from the Music folder on the iPod instead."
        case .artwork(let album):
            "This iPod shows the cover of \u{201C}\(album)\u{201D} from the album's folder in its Music folder, not from the library. Put the new cover there as cover.jpg instead."
        }
    }

    static func message(for error: ConversionQueueError) -> String {
        switch error {
        case .fileMissing(let title): "\u{201C}\(title)\u{201D} has no file on the iPod."
        case .notScanned(let title): "\u{201C}\(title)\u{201D} hasn't been checked yet."
        case .notConvertible(let title, let reason): "\u{201C}\(title)\u{201D} can't be converted: \(reason)"
        }
    }

    static func message(for error: MetadataError) -> String {
        switch error {
        case .invalidYear(let text): "\u{201C}\(text)\u{201D} isn't a year. Type four digits, like 1995."
        }
    }

    static func message(for error: AudioConversionError) -> String {
        switch error {
        case .noAudioTrack(let url): "\(url.lastPathComponent) has no audio track."
        case .cannotDecode(let what): "Couldn't decode \(what)."
        case .cannotEncode(let target): "Couldn't encode to \(target.label)."
        case .writerFailed: "The converted file couldn't be written."
        }
    }

    static func message(for error: AudioImport.ImportError) -> String {
        switch error {
        case .unreadable(let url):
            "Clickwill can't read \(url.lastPathComponent). Choose an MP3, AAC, Apple Lossless, WAV, AIFF or FLAC file."
        case .unsupportedFormat(let url, let reason): "\(url.lastPathComponent): \(reason)"
        }
    }

    static func message(for error: BackupRestoreError) -> String {
        switch error {
        case .notConnected:
            "Connect the iPod this backup came from to restore it."
        case .pendingChanges(let count):
            "There \(count == 1 ? "is 1 unwritten change" : "are \(count) unwritten changes"). Write or discard \(count == 1 ? "it" : "them") first - restoring replaces the library they were made on."
        }
    }

    static func message(for error: WriteBlocked) -> String {
        switch error {
        case .demoCopy: "This is a demo copy, so nothing is written to the iPod."
        case .notFromDevice: "The library isn't from a connected iPod, or it hasn't finished loading."
        case .permissionChanged: "Experimental writing for this iPod was turned off. Nothing was written."
        }
    }

    static func message(for failure: FeedbackSubmission.Failure) -> String {
        switch failure {
        case .offline:
            "Clickwill couldn't reach clickwilldev.com. Check your internet connection and try again. Your message is still here."
        case .rejected:
            "The message couldn't be sent. Make it shorter, or leave out the diagnostic report, and try again."
        case .busy:
            "Too many messages reached me today. Please try again tomorrow. Your message is still here."
        case .server:
            "Something went wrong on clickwilldev.com. Try again in a few minutes. Your message is still here."
        }
    }

    static func message(for error: AudioCD.ReadError) -> String {
        switch error {
        case .notAnAudioCD(let url): "\(url.lastPathComponent) isn't an audio CD."
        case .noAudioTracks: "This disc has no audio tracks."
        }
    }

    static func message(for error: MusicBrainz.LookupError) -> String {
        switch error {
        case .busy: "MusicBrainz is busy right now. Try again in a moment."
        case .server(let status): "MusicBrainz answered with an error (\(status))."
        case .unreadableResponse: "MusicBrainz sent an answer Clickwill couldn't read."
        case .tooLarge: "MusicBrainz sent an answer too large to read."
        }
    }

    /// A repair during the write that did not happen. Repairs run on
    /// every write, so the next one will try again.
    static func message(for problem: RepairPipeline.Problem) -> String {
        switch problem.step {
        case .coverOwners:
            "A merged song's cover couldn't be moved to the copy that stays, so that song may show no cover. The next write tries again."
        case .trackImages:
            "Some songs may not show their album cover while they play. The next write tries again."
        case .imageLinks:
            "Some songs may not show their album cover on the iPod. The next write tries again."
        case .coverCounts:
            "Some albums may not show their cover on every song. The next write tries again."
        }
    }

    /// Files of removed tracks that the deletion rule does not touch (a folder,
    /// a link, something outside the music folder) - they stay on the iPod for good.
    static func keptFiles(_ urls: [URL]) -> String {
        let names = urls.map(\.lastPathComponent).sorted()
        let listed = names.count > 3 ? names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more" : names.joined(separator: ", ")
        return names.count == 1
            ? "\(listed) stays on the iPod. It isn't a plain audio file in the iPod's music folder, so Clickwill doesn't delete it."
            : "\(names.count) files stay on the iPod: \(listed). They aren't plain audio files in the iPod's music folder, so Clickwill doesn't delete them."
    }

    /// One line of the post-write report: what it concerns and why.
    static func line(_ problem: WriteProblem) -> String {
        "\(problem.subject): \(reason(problem.reason))"
    }

    /// A file or track that was not added to the change list.
    static func line(_ refusal: QueueRefusal) -> String {
        let reason = switch refusal.reason {
        case .cannotPlay(let reason): reason ?? "the iPod can't play this file"
        case .alreadyQueued: "already in the list of changes"
        case .notAudio: "not an audio file Clickwill can read"
        case .noSongsToMatch: "this album has no songs to match"
        case .error(let error): message(for: error)
        }
        return "\(refusal.subject): \(reason)"
    }

    /// The path of a disc track that was not ripped.
    static func line(_ failure: CDRipper.Failure) -> String {
        switch failure.reason {
        case .folderNotCreated(let error): "Couldn't create \(failure.subject): \(error.localizedDescription)"
        case .trackMissing: "\(failure.subject): the track file isn't on the disc"
        case .error(let error): "\(failure.subject): \(message(for: error))"
        }
    }

    /// A notice above the file list in the add sheet.
    static func line(_ note: ImportSession.Note) -> String {
        switch note {
        case .unreadable(let error): message(for: error)
        case .cannotPlay(let title, let reason): "\(title): \(reason ?? "the iPod cannot play this")"
        case .unreadableCover(let url): "Clickwill can't read \(url.lastPathComponent). Choose a JPEG, PNG or HEIC image."
        }
    }

    private static func reason(_ reason: WriteProblem.Reason) -> String {
        switch reason {
        case .error(let error): message(for: error)
        case .stillNotPlayable: "the converted file is still not playable"
        case .notPlaced(let error): "added, but not at the chosen place (\(message(for: error)))"
        case .keptByRule: "it isn't an audio file in the iPod's music folder, so Clickwill left it alone"
        case .notDeleted(let error): "it couldn't be deleted (\(message(for: error)))"
        }
    }

    /// Why this iPod cannot be written to - for the label and the hint.
    static func readOnlyMessage(_ reason: ReadOnlyReason?) -> String {
        switch reason {
        case let reason?:
            return readOnlyFact(reason)
        case nil:
            return "This iPod can't be written to."
        }
    }

    /// Why there is no library on screen.
    static func message(for failure: LibraryModel.Failure) -> String {
        switch failure {
        case .loading(let error):
            return message(for: error)
        case .disconnected(let lost):
            return "The iPod was disconnected. \(lost) unsaved \(lost == 1 ? "change was" : "changes were") discarded."
        }
    }

    /// Why the library on screen cannot be written.
    static func message(for unavailable: LibraryModel.WriteUnavailable) -> String {
        switch unavailable {
        case .device(let reason): return readOnlyMessage(reason)
        case .snapshot: return "This library came from a snapshot, so writing is turned off."
        }
    }
}
