# iPod database byte map

What sits under which byte. One file, so that nobody has to work it out again.

**Why this exists.** Field 0x160 was described as "meaning unknown" for a long
time. Meanwhile we fixed, one after another, 0x7E, the 0x7C/0x80 pair, 0xA8,
the album record identity and 0x124 - five fixes, each of which landed in the
database correctly and **none of which changed anything on the device**,
because none of those fields is the path the iPod takes to the artwork. 0x160
was that path all along.

**The rule that follows:** a field whose distribution lines up with the failure
is checked *because* nobody knows what it does - not set aside for that
reason. "I don't know what this does" is a reason to measure, not to skip.

## How to read the tables

The **confidence** column:

| | meaning |
|---|---|
| **measured** | checked on a real database, with numbers in the "how we know" column |
| **from the format** | from format descriptions, consistent with what we see, but not checked separately |
| **unknown** | we do not know; if something depends on it, **measure before treating it as irrelevant** |

All numbers are little-endian. Offsets are counted from the start of the record.

---

## `mhit` - track (624 B header)

| offset | width | what it is | confidence | how we know |
|---|---|---|---|---|
| 0x00 | 4 | `mhit` | | |
| 0x04 | 4 | header length (624) | measured | |
| 0x08 | 4 | total length including the `mhod`s | measured | |
| 0x0C | 4 | number of `mhod` children | measured | |
| 0x10 | 4 | `uniqueID` - the browse tables hold it, **never change it** | measured | changing it scrambles the menu |
| 0x14 | 4 | visible (1) | from the format | |
| 0x18 | 4 | file type, a four-character code (`MP3 `) | measured | |
| 0x1C | 1 | type 1 | from the format | |
| 0x1D | 1 | type 2 | from the format | |
| **0x1E** | 1 | **compilation flag** - moves the album to the "Compilations" group at the end of Cover Flow | measured | the iPod reads it on the fly, without rebuilding the tables |
| 0x1F | 1 | rating | from the format | |
| 0x20 | 4 | modification date (Mac time) | measured | |
| 0x24 | 4 | file size in bytes | measured | |
| 0x28 | 4 | length in milliseconds | measured | |
| 0x2C | 4 | track number | measured | |
| 0x30 | 4 | number of tracks on the disc | measured | |
| 0x34 | 4 | year | measured | |
| 0x38 | 4 | bitrate (kb/s) | measured | |
| 0x3C | 4 | sample rate in the **upper 16 bits**; the lower ones are preserved | measured | |
| 0x50 | 4 | play count | from the format | |
| 0x54 | 4 | zeroed on insertion | unknown | |
| 0x58 | 4 | last played (Mac time) | from the format | |
| 0x5C | 4 | disc number | measured | |
| 0x60 | 4 | number of discs | measured | |
| 0x68 | 4 | date added (Mac time) | measured | |
| **0x70** | 8 | **the track's `persistentID`** - `ArtworkDB` links the image owner by it | measured | `mhii` 0x14 = this value |
| **0x7C** | 2 | **artwork count**. The field is **two bytes** wide | measured | writing a 4-byte zero wiped 0x7E in 38 records |
| **0x7E** | 2 | **artwork marker, always `0xFFFF`** - also when 0x7C = 0 | measured | 1604/1604 records written by iTunes |
| **0x80** | 4 | **artwork source size** = the length of the image embedded in the file. Rule: `mhii` 0x30 = 0x80 + 0x7C | measured | holds for 1555/1612 tracks; nano 2G: 0x80 = 125953 = the image from the APIC frame, to the byte |
| 0x88 | 4 | sample rate as a `Float` - the second place where iTunes keeps it | measured | `0x472c4400` = 44100.0, always consistent with 0x3C |
| 0x98 | 4 | zero even in working albums | unknown | checked - does not differ |
| 0x9C | 4 | as above | unknown | as above |
| 0xA0 | 4 | as above | unknown | as above |
| **0xA4** | 1 | **1 = the track points to an image (0x160), 2 = it does not** | measured 2026-09-27 | Classic: of Apple's records, 1610 with 0x160 have 1, 8 without have 2; the only exceptions are albums we added and "Ok Computer" written by Music. nano 2G after Finder (no `ArtworkDB`): 2 in every one. We set it together with 0x160 |
| **0xA8** | 8 | **second copy of the `persistentID`** (a copy of 0x70) | measured | repairing it changed nothing on the device - the field exists, but it is not about artwork |
| **0x120** | 4 | **album record index** (`mhia` 0x10) | measured | 1603/1603 tracks point to the `mhia` with the same title |
| **0x124** | 8 | **identifier of the Music library the track came from** (hypothesis) | medium | in a database written by Apple: `8807…` (= `mhbd` 0x24) has 309 tracks added 2024-04…2026-05, `f4ac…` 1269 tracks added within 10 days (2025-07-30…08-08), zero for 25 tracks from 2025-08-25. It is not "the iPod database it was created in" (the dates interleave), but most likely two libraries on a computer. Filling it in changed nothing on screen. The app writes nothing here; new tracks inherit the template's value. Clickwill is not a Music library, so without a measurement there is nothing "correct" to write here |
| 0x12C | 4 | zeroed on insertion | unknown | |
| 0x148 | 4 | zeroed on insertion | unknown | |
| 0x15C | 4 | one value across the whole library | unknown | a control next to 0x160 |
| **0x160** | 4 | **image record identifier** (`mhii` 0x10) - **this is the path the iPod takes to the artwork during playback** | measured | 1558/1558 non-zero values point to an existing record; zero was found exactly on the albums without artwork |
| 0x164 | 4 | one value across the whole library | unknown | a control next to 0x160 |
| 0x1F4 | 4 | set to `uniqueID + 1` | unknown | that is what iTunes does |

### Two paths to the artwork - this is not a needless duplication

The symptom "the artwork is in Cover Flow, but not during playback" came from
the iPod having **two different paths**, and both must be healthy:

| where | linked by | how much it needs |
|---|---|---|
| Cover Flow, album lists | `mhii` 0x14 = `mhit` 0x70 | **one** track per album |
| the Now Playing screen | `mhit` 0x160 = `mhii` 0x10 | **every** track separately |

Hence "Patient Number 9 - artwork on 1 of 13": that one track was the owner of
the image record.

---

## `mhod` - a text container (24 B header)

After the header: the text length (4 B), the encoding (4 B), two words, then the
characters **in UTF-16LE from +16**. In `ArtworkDB` the layout is different - see below.

| type | what it is | confidence |
|---|---|---|
| 1 / 2 / 3 / 4 | title / path / album / artist | measured |
| 5 / 6 / 8 / 12 | genre / file type / comment / composer | measured |
| 22 | album artist | measured |
| 23 / 27 / 28 / 29 | sort: artist / title / album / album artist | measured on 1619 tracks |
| 50–53 | binary data: smart playlists, **browse table (52)**, **jump table (53)** | measured |
| 100 / 102 | playlist item data, preference | measured |
| 200 / 201 / 202 | album / artist / artist sort in the `mhla` section | measured |

**The order in the iPod menu is not sorted on the fly** - it is stored as ready
permutations in types 52 and 53 in the master playlist. The master playlist appears
in **two** `mhsd` sections, and both have to be rebuilt.

---

## `mhia` - an album record in `iTunesDB` (88 B header)

| offset | width | what it is | confidence |
|---|---|---|---|
| 0x10 | 4 | album index - this is what `mhit` 0x120 points to | measured |
| 0x14 | 4 | a value unique in 116 of 118 records | **unknown** |
| 0x18 | 8 | the album's `persistentID` - upper word `0x00000002` or `0x00000102`, never a full random 64 bits as for a track | measured (116/118) |
| 0x20 | 8 | does not decide how artwork is linked | unknown |

**A known defect, not fixed yet:** The Wall, Patient Number 9 and Ordinary
Man share the value at 0x14, because we copied it from the template. No symptom
of it is visible.

---

## `ArtworkDB`

The layout differs from `iTunesDB` in two places, and mixing them up misaligns the file:
an `mhod` of type 2 is a **container** with a nested `mhni`, and text starts
**at +12 after the header**, not at +16.

### `mhfd` - file header (0x84 B)
| offset | width | what it is |
|---|---|---|
| 0x10 | 4 | 6 (Music, constant in 41 backups) |
| 0x14 | 4 | number of sections: 3 |
| 0x1C | 4 | **next free image identifier** |
| 0x20 | 16 | an identifier that appears in no other iPod file; the same value in 47 of our backups, but **Music wrote a new one on save on 2026-09-27** - it is not constant |
| 0x30 | 4 | 1 (constant) |
| 0x3C | 8 | an identifier that appears in no other file; unchanged after a Music save |

`mhsd` sections: type 1 = image list (`mhli`), type 2 = album list (`mhla`,
**empty on this device**), type 3 = format list (`mhlf`).

### `mhii` - image record
| offset | width | what it is | confidence |
|---|---|---|---|
| 0x10 | 4 | image identifier - `mhit` 0x160 points to it | measured |
| 0x14 | 8 | `persistentID` of the **owner track** | measured |
| 0x30 | 4 | source size; rule `= mhit 0x80 + 0x7C` | measured |
| 0x38 | 4 | how many tracks it applies to; usually = the album's track count | measured - **does not control artwork visibility** |
| 0x3C | 4 | 1 in all 144 | constant |
| 0x48, 0x50 | 8 + 8 | double NaN in all 144 | constant |

The `mhii` children written by Music: three `mhod`s of type 2 and one of type 6 (`mhaf`, all
zeros). A record we build from scratch skips `mhaf` - we do not know what it
means, and the nano 2G firmware is older than it.

### `mhni` - image variant
| offset | width | what it is |
|---|---|---|
| 0x10 | 4 | format identifier (1055 / 1060 / 1061) |
| 0x14 | 4 | offset in the `.ithmb` file |
| 0x18 | 4 | size in bytes |
| 0x20 | 2 | height |
| 0x22 | 2 | width |
| 0x28 | 4 | the size once more (= 0x18) |

The `mhod` child of type 3 carries the file name (`:F1060_1.ithmb`), with the text **from +12**.

### Formats (`mhif` 0x10 / 0x14)
| id | size | slot | where it shows |
|---|---|---|---|
| 1055 | 128×128 | 32768 B | lists, the Now Playing screen |
| 1060 | 320×320 | 204800 B | Cover Flow |
| 1061 | 55×55, stride 56 | 6160 B | list thumbnails |
| 1027 | 100×100 | 20000 B | nano 2G, the Now Playing screen - **confirmed on the device on 2026-10-09** (the image straight, the colors correct, one shared slot for 13 `mhii`s) |
| 1031 | 42×42 | 3528 B | nano 2G (from the firmware description) - written together with 1027; where it shows: not checked |

Row stride: the bytes of a row are aligned to 4 (`AlignRowBytes` in the device
description); that explains 56 px for 55 px. For 42 and 100 px there is no
padding. A wrongly assumed alignment would show a diagonally sheared image on screen.

Pixels: **RGB565 little-endian**. Every image record has the full set of three
variants - checked on all 138.

---

## `mhbd` - database header

| offset | width | what it is |
|---|---|---|
| 0x10 | 4 | version |
| 0x14 | 4 | number of `mhsd` sections |
| 0x18 | 8 | database identifier (zeroed when computing hash58) |
| 0x24 | 8 | a second identifier - most likely of the Music library that synced last; the same value as in `mhit` 0x124 of some tracks | measured: `8807a8f8c5f766a3` |
| **0x30** | 2 | **signing scheme**: 0 none, 1 hash58, 2 hash72, 4 hashAB | measured: 1 on the Classic; the meanings of 2 and 4 per libgpod |
| 0x32 | 20 | a block zeroed when computing hash58 |
| **0x58** | 20 | **hash58 signature** (HMAC-SHA1, key from the FireWire GUID) |
| 0x50 | 4 | Classic 1, nano 2G 0 - meaning unknown | measured 2026-09-27 |
| 0x54 | 4 | Classic 159, nano 2G 0 - meaning unknown | measured 2026-09-27 |
| 0x70 | 2 | Classic 3, nano 2G (unsigned) 0 - goes together with the presence of hash72 | measured |
| 0x72 | 46 | **hash72 signature** - Music writes it on the Classic too (it starts with `01 00`), the device checks only hash58 |
| 0xAB | 57 | hashAB signature (nano 6G/7G); all zeros on the Classic |

Without a valid signature at 0x58 the iPod treats the database as someone else's.

**A mistake until 2026-09-24:** we read the scheme from 0x72. It came out as 1, because
the hash72 signature starts there (`01 00`). On the Classic the result was right by
accident, but a nano 5G database (0x30 = 2, and `01 00` at 0x72 too) would have been taken
for hash58 and signed with the wrong algorithm. Caught when comparing with other
descriptions of the format, confirmed on a database from a backup: 0x30 = 1, and
`ipodctl roundtrip` on a database written by Apple Music matches to the byte.

---

## What we **do not** know, and what follows from it

Unknown fields from the tables above: `mhit` 0x54, 0x12C, 0x148, 0x15C, 0x164, 0x1F4,
the pieces 0x98/0x9C/0xA0, `mhia` 0x14 and 0x20.

That does not mean they are unimportant. It means **nobody has measured them yet**.
The next time something on the device does not work while the database looks correct,
the cheapest move is a scan of all header offsets for the one that splits the
library along the line of the failure. That scan found 0x124 and 0x160.
It takes a dozen seconds.
