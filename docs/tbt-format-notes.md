# TBT format recovery notes

Status: preliminary observations from `Rose Of Sharyn.tbt` and the two demo
files bundled with TabIt 2.03. A field is not considered understood until
controlled samples confirm it.

## Confirmed envelope

| Offset | Size | Meaning |
| --- | ---: | --- |
| `0x00` | 3 | ASCII signature prefix `TBT` |
| `0x03` | 1 | Format marker: `o` in 1.6 demos, `r` in the 2.0 sample |
| `0x04` | 1 | Legacy one-byte tempo |
| `0x05` | 1 | Track count |
| `0x06` | variable | Pascal-1 display version; sample value `2.0` |
| `0x0b` | 1 | Feature flags; `0x10` enables alternate-time regions |
| `0x28` | 2 | Bar count for marker `0x70` and newer |
| `0x2a` | 2 | Shared space count for marker `0x6f` |
| `0x2e` | 2 | Actual tempo |
| `0x30` | 4 | Little-endian compressed length of payload 0 |
| `0x34` | 4 | CRC-32 of all compressed bytes after the header |
| `0x38` | 4 | Little-endian total file length |
| `0x3c` | 4 | CRC-32 of header bytes `[0, 60)` |
| `0x40` | variable | First RFC 1950 zlib stream |
| following stream | variable | Second RFC 1950 zlib stream |

The sample is 4,540 bytes. Its payloads are:

1. Offset `0x40`, 855 compressed bytes, 1,936 decompressed bytes. This contains
   title, artist, album, author comments, lyrics, and additional binary fields.
2. Offset `0x397`, 3,621 compressed bytes, 43,098 decompressed bytes. This is
   dense binary song data and appears to contain repeated track/measure/event
   records.

The bundled `Demo.tbt` and `Drum Demo.tbt` use version `1.6` and the `TBTo`
marker. They retain the same 64-byte envelope, length fields, and two-stream
layout. Both parse with the same envelope reader.

## Executable analysis

The Inno Setup installer contains `TabIt.exe`, the two demo files, help, and
trial-support data. Ghidra 12.2 successfully imports and analyzes the 32-bit
x86 executable.

Strings and Delphi runtime type information confirm:

- The application was built with Borland Delphi.
- It embeds zlib 1.2.3 and its error classes.
- Domain/UI type names include `TTrackData` and `TMeasureItemEvent`.
- Save/open action names and `.tbt` file associations remain in the binary.

Independent format documentation and parser behavior were cross-checked
against Ghidra findings and all three authentic files. See
`THIRD_PARTY_NOTICES.md` for attribution.

## Next controlled samples

Create each file in the Windows TabIt application from the same empty baseline,
changing one property per file:

1. Empty score and one-note score.
2. One note at each string and fret.
3. Quarter, eighth, dotted, tied, and rest durations.
4. One chord and simultaneous notes.
5. Tempo, time signature, key signature, and tuning changes.
6. Repeat, alternate ending, section marker, and text.
7. Bend, slide, hammer-on, pull-off, vibrato, palm mute, and harmonic.
8. One versus two tracks, then guitar versus bass/drums.
9. Metadata fields changed independently.

Binary diffs of the decompressed payloads should reveal record boundaries and
field encodings. A minimum useful corpus is the empty baseline plus these
single-variable files.

## Implementation status

The app decodes 20-byte note spaces, per-string effects, track metadata, bar
lines, and alternate-time regions for markers `0x6f` through `0x72`. The
writer re-encodes edited note streams and recomputes both CRCs while preserving
metadata, bar data, timing regions, and track-effect blobs from the source.
Saving uses a new copy so the source remains recoverable.
