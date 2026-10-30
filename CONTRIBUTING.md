# Contributing to Clickwill

Thanks for helping. The most useful thing you can bring is an iPod Clickwill
hasn't been confirmed on yet: every model works a little differently, and a
model is confirmed only from measurements on the real thing.

## Report an iPod

Clickwill opens a model it hasn't confirmed read-only. To report one:

1. Connect the iPod, open **Overview** and click **Run Diagnostics…**
2. Click **Send Report…**. The whole report is shown before it goes. It has no
   GUID, serial number, iPod name, song titles or folder names.

Or open a [New iPod issue](../../issues/new?template=new-ipod.yml) and paste the
report: **Send Report…** › **Copy Report**. If every required check passes,
**Settings › Experimental iPods** lets you write to that one iPod, and the
answer to "Were the changes visible on the iPod?" after the first write is
part of the evidence.

## Confirm a model in code

A model is confirmed in one file:
[`Sources/ITDBKit/Device/ConfirmedModels.swift`](Sources/ITDBKit/Device/ConfirmedModels.swift).
It lists the firmware families whose unsigned database Clickwill writes, the
families that look artwork up song by song, the measured artwork formats and
the measured `Play Counts` layouts. Each entry says what it was measured on.

A new USB product goes into `USBIdentity` as well. Nothing else should need to
change; if it does, explain why in the pull request.

### The evidence a pull request needs

- **The diagnostic report**, from the app or `swift run ipodctl diagnose`.
  Every required check passed, and the `measurements:` lines are included.
- **The byte-for-byte rebuild**: `swift run ipodctl roundtrip` says the writer
  reproduces your database unchanged.
- **A test on the iPod**, each step written by Clickwill and then checked on
  the iPod itself:
  - rename a song
  - add an album with artwork, and check the artwork in Cover Flow and while it plays
  - change an album's artwork
  - delete a song
  - restore the backup from before the first write
- **The firmware version** the test ran on, and whether the iPod also runs
  Rockbox.
- **Tests** for any new rule, on a synthetic library in a temporary folder, like
  the ones in `Tests/`. Never commit your own database, artwork or audio files.

Before writing to your iPod: close Apple Music, and keep the backup Clickwill
makes before the first write (`swift run ipodctl backup` makes one by hand).

## Developer Mode

**Settings › Experimental iPods › Developer Mode** is for developers measuring a
model that isn't confirmed yet. It lifts the confirmed lists, the USB check and
the list of measured artwork formats, so you can write to a new model or to a
disk image with an iPod folder on it. It never skips the signature, identity
conflicts or the backup before a write.

It needs the Experimental iPods switch on, asks first with a warning, and ends
when Clickwill quits. In Clickwill 0.4.1 the switch exists only in a build from
this repository; later releases have it too. On the command line, `ipodctl`
takes `--developer` for the same thing.

Use it on an iPod whose library you can restore. To show that a model works for
everyone, the test above should pass with Experimental iPods alone, without
Developer Mode.

Building and the test commands are in the [README](README.md#building).

## Checking your iPod with an AI coding assistant

If you use an assistant that runs commands in a terminal, such as Claude Code or
Codex, open it in a clone of this repository, connect the iPod and paste:

```text
Help me check whether Clickwill can safely write to my iPod, and collect the
evidence CONTRIBUTING.md asks for. Read CONTRIBUTING.md and README.md first.

Rules:
- Read-only first. Never write to the iPod, and never run a command with
  --apply, --developer, restore or remove, without asking me and waiting for my yes.
- Before any write: Apple Music is closed, and a backup exists
  (swift run ipodctl backup, then swift run ipodctl snapshots).
- Never put my GUID, serial number, iPod name, song titles, file names or my
  database, artwork or audio files into an issue, a commit or a message.
  `ipodctl info` prints the GUID: don't copy its output anywhere.

Steps:
1. export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer, then
   swift build.
2. swift run ipodctl diagnose and swift run ipodctl roundtrip. Explain every
   check that didn't pass and what the measurements lines say about it.
3. If every required check passed, walk me through the test on the iPod from
   CONTRIBUTING.md in the Clickwill app, one step at a time. I do each step
   myself; after each, check the result read-only (diagnose, roundtrip,
   ipodctl library) and ask me what the iPod shows.
4. Draft the New iPod issue: model, firmware, the diagnose output, the
   roundtrip result, and the result of each step. If I want a pull request,
   change only Sources/ITDBKit/Device/ConfirmedModels.swift (and USBIdentity for
   a new USB product), add tests on a synthetic library, run Tools/check.sh,
   and commit with git commit -s.
```

## Pull requests

- One change per pull request, with what it changes and why.
- `Tools/check.sh` passes: the core tests and the Mac build.
- Comments, names and messages in English.
- Sign off your commits (`git commit -s`): the `Signed-off-by` line says you
  wrote the change, or have the right to submit it, under the project's license
  ([Developer Certificate of Origin](https://developercertificate.org)).

Clickwill is licensed under the GNU General Public License, version 3. Your
contribution is licensed the same way.

Confirming a model changes what Clickwill does for everyone who owns one, so a
pull request that confirms a model is merged only with the evidence above.
