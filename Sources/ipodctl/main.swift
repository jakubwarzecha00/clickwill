import Foundation
import ITDBKit

// Developer tool for ITDBKit. Deliberately without external dependencies -
// the core must not have any, so the CLI does not either.
//
// Each command in its own file in Commands/ (a `...Command` type with `run()`),
// shared helpers in Support/. Here only the help text and command dispatch.

let usage = """
ipodctl - \(ProductInfo.name) developer tool

  usage: ipodctl COMMAND [options] - the command always comes first

  --volume IPOD         which iPod: nano, classic, GUID or path (required when several are connected)

  info                  information about the connected iPod
  hash58                database signature verification (gate T1.2)
  library               library summary
  check [--remove-orphans [--apply]]
                        database consistency with files on disk; --remove-orphans deletes files without an entry
  plays [--merge [--apply]]
                        statistics counted by the iPod; --merge merges them into the database and deletes the file
  artwork [--extract ID --out FILE.png]
                        artwork: summary or extracting one image
  artwork --check-counts [--apply]
                        albums whose artwork the app sees but the iPod does not:
                        the image record declares fewer tracks than the album has
  artwork --add ALBUM --file IMAGE [--unverified-formats] [--apply]
                        first artwork for an album without artwork (new mhii + slots + mhia);
                        without ArtworkDB it creates one from the formats the firmware gives.
                        --unverified-formats: hardware trial of a format outside the confirmed ones
  artwork --per-track ALBUM [--apply]
                        album artwork in a separate mhii for each track (the same slots);
                        the nano 2G looks up artwork by track, not by album
  dump [--out FILE]     the whole library as JSON
  roundtrip             GATE: whether the writer reproduces the database byte for byte
  rewrite               rewriting the database to the iPod unchanged (hardware test)
  fix-sort [--apply]    repairing sort fields that split albums into several covers
  set-field --album A --field F --value V [--apply]
                        setting a text field for all tracks of an album
                        (F: albumartist, artist, album, sortartist, sortalbum,
                         sortalbumartist, genre, composer; --value \"\" clears the field)
  order [--letter X]    album order as the browse table laid it out
  order --check         blocks lying outside their place in the alphabet
  order --capture       remember the current order as the intended one
  order --intent        compare the device with the remembered intent
  order --reapply [--apply]
                        apply the intent again (after Music regenerated the tables)
  order --repair [--apply]
                        reassembling albums scattered across the table
  order --move ALBUM (--before ALBUM | --after ALBUM | --at N | --start)
        [--jump derived|flat] [--apply]
                        moving an album in display order; the jump bar
                        computed from the layout (derived) or flattened (flat)
  tracks --album A [--move TRACK (--before TRACK | --after TRACK | --at N)]
        [--renumber] [--apply]
                        track order in an album; --renumber assigns 1..N by layout
  audio [--fix ID[,ID] | --fix-all] (--keep-originals FOLDER | --discard-originals) [--apply]
                        file formats: what the iPod plays and what it does not; --fix transcodes
  add FILE|FOLDER ... [--title T] [--artist A] [--album B] [--track N] [--apply]
                        adding tracks to the library; without --apply only a preview
                        with invariant checks (permutations, bars, signature).
                        Field overrides work only with a single file.
  copy --from IPOD --album A [--album B ...] [--artist X] [--apply]
                        albums from another iPod: audio from its file, descriptions from its database;
                        skips tracks the target already has
  remove (--dead | --id N,N | --orphan-albums) [--apply]
                        removing tracks from the database with remapping of the tables
  backup [--note TEXT]  backup of the database and artwork

  Every write checks that Music is closed, and merges pending plays.
  --allow-music         write even with Music running (changes to the tables will not survive)
  snapshots             list of backups
  verify <id>           checking a backup's checksums
  restore <id>          restoring a backup to the device
"""

/// The command named by the first argument. An error the command did not
/// handle itself ends the program with the message `error: ...` and exit code 1 - this
/// is the only place that ends the process.
let command: ((Invocation) async throws -> Void)? = switch CommandLine.arguments.dropFirst().first {
case "info": InfoCommand.run
case "sysinfo": SysInfoCommand.run
case "hash58": Hash58Command.run
case "library": LibraryCommand.run
case "paths": PathsCommand.run
case "coverflow": CoverFlowCommand.run
case "duplicates": DuplicatesCommand.run
case "check": CheckCommand.run
case "plays": PlaysCommand.run
case "artwork": ArtworkCommand.run
case "dump": DumpCommand.run
case "roundtrip": RoundtripCommand.run
case "rewrite": RewriteCommand.run
case "fix-sort": FixSortCommand.run
case "set-field": SetFieldCommand.run
case "order": OrderCommand.run
case "tracks": TracksCommand.run
case "audio": AudioCommand.run
case "add": AddCommand.run
case "copy": CopyCommand.run
case "demo-snapshot": DemoSnapshotCommand.run
case "remove": RemoveCommand.run
case "backup": BackupCommand.run
case "snapshots": SnapshotsCommand.run
case "verify": VerifyCommand.run
case "restore": RestoreCommand.run
default: nil
}

let name = CommandLine.arguments.dropFirst().first
if let command {
    do {
        try await command(Invocation(arguments: Array(CommandLine.arguments.dropFirst())))
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
} else if let name {
    // A typo in the command name must not look like success in a script.
    let problem = name.hasPrefix("--") ? "the command always comes first, before \(name)" : "unknown command '\(name)'"
    FileHandle.standardError.write(Data("error: \(problem)\n".utf8))
    print(usage)
    exit(1)
} else {
    print(usage)
}
