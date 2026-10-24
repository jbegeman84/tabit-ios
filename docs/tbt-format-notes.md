# TBT format recovery notes

Status: preliminary observations from `Rose Of Sharyn.tbt` and the two demo
files bundled with TabIt 2.03. A field is not considered understood until
controlled samples confirm it.

## Confirmed envelope

| Offset | Size | Meaning |
| --- | ---: | --- |
| `0x00` | 3 | ASCII signature prefix `TBT` |
| `0x03` | 1 | Format marker: `o` in 1.6 demos, `r` in the 2.0 sample |
| `0x07` | variable | Null-terminated format version; sample value `2.0` |
| `0x30` | 4 | Little-endian compressed length of payload 0 |
| `0x38` | 4 | Little-endian total file length |
| `0x40` | variable | First RFC 1950 zlib stream |
| following stream | variable | Second RFC 1950 zlib stream |

The sample is 4,540 bytes. Its payloads are:

1. Offset `0x40`, 855 compressed bytes, 1,936 decompressed bytes. This contains
   title, artist, album, author comments, lyrics, and additional binary fields.
2. Offset `0x397`, 3,621 compressed bytes, 43,098 decompressed bytes. This is
   dense binary song data and appears to contain repeated track/measure/event
   records.

The remaining header fields are unknown. Values that resemble checksums must
not be labelled as checksums until mutation experiments confirm them.

The bundled `Demo.tbt` and `Drum Demo.tbt` use version `1.6` and the `TBTo`
marker. They retain the same 64-byte envelope, length fields, and two-stream
layout. Both parse with the same envelope reader.

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

## Implementation rule

Writing `.tbt` files remains disabled until record boundaries, counts, and
integrity fields are known. Reader work may expose confirmed fields while
retaining all opaque bytes for lossless pass-through.
