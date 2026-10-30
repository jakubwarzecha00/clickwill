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

## Measuring with a Debug build

A Debug build from this repository has **Developer Mode** in **Settings ›
Experimental iPods**, and `ipodctl` takes `--developer`. It lifts the confirmed
lists and the USB check, so you can measure a model, or write to a disk image
with an iPod folder on it. It never skips the signature, identity conflicts or
the backup before a write. Use it on an iPod whose library you can restore.

Building and the test commands are in the [README](README.md#building).

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
