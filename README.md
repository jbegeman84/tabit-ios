# Tabit

Tabit is an independent, native iOS reader and editor for legacy TabIt
tablature (`.tbt`) documents.

The project currently contains:

- `TabitFormat`: a Swift library that validates the known 64-byte envelope,
  inflates each concatenated zlib payload, and retains the original bytes.
- `tbt-inspect`: a command-line inspector that reports structure and embedded
  printable strings as JSON.
- `Tabit.xcodeproj`: a native SwiftUI iPhone/iPad reader that imports `.tbt`
  files through the system Files picker and shows recovered text and format
  details.
- Fixture-based tests for valid files and damaged headers.

No original TabIt source code or proprietary assets are included.

## Build and test

```sh
swift test
swift run tbt-inspect "/path/to/song.tbt"
```

## Run the iOS app

1. Open `Tabit.xcodeproj` in Xcode.
2. Select the `Tabit` scheme and an iPhone simulator.
3. Run the app.
4. Select **Choose File** and open a `.tbt` document from Files.

The checked-in Xcode project is generated from `project.yml` with XcodeGen.
Run `xcodegen generate` after changing project settings.

## Current scope

The app is currently a reader/inspector. The parser intentionally exposes
opaque payloads. Field-level notation models, playback, editing, and writing
support will be added only as fields are confirmed using controlled sample
files. Until then, retaining `originalData` prevents unknown data from being
silently discarded.

See `docs/tbt-format-notes.md` for confirmed findings and the next experiments.
