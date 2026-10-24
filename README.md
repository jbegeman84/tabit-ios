# Tabit

Tabit is an independent, native iOS reader and editor for legacy TabIt
tablature (`.tbt`) documents.

The project currently contains the first format-recovery milestone:

- `TabitFormat`: a Swift library that validates the known 64-byte envelope,
  inflates each concatenated zlib payload, and retains the original bytes.
- `tbt-inspect`: a command-line inspector that reports structure and embedded
  printable strings as JSON.
- Fixture-based tests for valid files and damaged headers.

No original TabIt source code or proprietary assets are included.

## Build and test

```sh
swift test
swift run tbt-inspect "/path/to/song.tbt"
```

## Current scope

The parser intentionally exposes opaque payloads. Field-level song models and
writing support will be added only as fields are confirmed using controlled
sample files. Until then, retaining `originalData` prevents unknown data from
being silently discarded.

See `docs/tbt-format-notes.md` for confirmed findings and the next experiments.
