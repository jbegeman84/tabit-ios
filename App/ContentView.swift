import SwiftUI
import TabitFormat
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var song: LoadedSong?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let song {
                    SongDetailView(song: song)
                } else {
                    EmptyLibraryView {
                        isImporting = true
                    }
                }
            }
            .navigationTitle("Tabit")
            .toolbar {
                if song != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isImporting = true
                        } label: {
                            Label("Open another file", systemImage: "folder")
                        }
                        .accessibilityIdentifier("openAnotherFileButton")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.tabitTablature],
            allowsMultipleSelection: false,
            onCompletion: importFiles
        )
        .alert(
            "Couldn’t Open File",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "The file could not be read.")
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasSecurityAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let document = try TBTDocument.parse(data)
            song = LoadedSong(
                summary: TBTSummary(document: document, fileName: url.lastPathComponent),
                score: try TBTScoreParser.parse(document)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoadedSong {
    let summary: TBTSummary
    let score: TBTScore
}

private struct EmptyLibraryView: View {
    let openFile: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Open a TabIt Song", systemImage: "music.note.list")
        } description: {
            Text("Choose a .tbt file from Files to inspect its recovered song information.")
        } actions: {
            Button("Choose File", action: openFile)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("chooseFileButton")
        }
        .padding()
    }
}

private struct SongDetailView: View {
    let song: LoadedSong
    @State private var selectedTrack = 0
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(song.score.title.isEmpty ? song.summary.fileName : song.score.title)
                    .font(.title2.bold())
                    .lineLimit(1)
                if !song.score.artist.isEmpty {
                    Text(song.score.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Picker("Section", selection: $section) {
                    Text("Tablature").tag(0)
                    Text("Song Info").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(.bar)
            .accessibilityIdentifier("songHeader")

            if section == 0 {
                TablatureView(
                    score: song.score,
                    selectedTrack: $selectedTrack
                )
            } else {
                SongInfoView(song: song)
            }
        }
        .accessibilityIdentifier("songDetail")
    }
}

private struct TablatureView: View {
    let score: TBTScore
    @Binding var selectedTrack: Int

    private var displayedTracks: [TBTTrack] {
        selectedTrack == -1 ? score.tracks : score.tracks.filter { $0.id == selectedTrack }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Instrument", selection: $selectedTrack) {
                    Text("All Tracks").tag(-1)
                    ForEach(score.tracks) { track in
                        Text("\(track.name) · \(track.instrumentName)").tag(track.id)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .accessibilityIdentifier("trackPicker")

                ForEach(displayedTracks) { track in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.name)
                                    .font(.headline)
                                Text(track.instrumentName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(track.stringCount) strings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        LazyVStack(spacing: 10) {
                            ForEach(systemRanges(for: track), id: \.lowerBound) { range in
                                TablatureSystem(
                                    track: track,
                                    barLines: score.barLines,
                                    spaces: range
                                )
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("tablatureView")
    }

    private func systemRanges(for track: TBTTrack) -> [Range<Int>] {
        stride(from: 0, to: track.spaceCount, by: 15).map {
            $0..<min($0 + 15, track.spaceCount)
        }
    }
}

private struct TablatureSystem: View {
    let track: TBTTrack
    let barLines: [TBTBarLine]
    let spaces: Range<Int>

    private let columnWidth: CGFloat = 22
    private let labelWidth: CGFloat = 34
    private let lineHeight: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let eventMap = Dictionary(uniqueKeysWithValues: track.events.map { ($0.space, $0) })

            for line in 0..<track.stringCount {
                let y = CGFloat(line) * lineHeight + 24
                var path = Path()
                path.move(to: CGPoint(x: labelWidth, y: y))
                path.addLine(to: CGPoint(x: size.width - 8, y: y))
                context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)

                let string = track.stringCount - line - 1
                context.draw(
                    Text(tuningLabel(for: string))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary),
                    at: CGPoint(x: 14, y: y)
                )
            }

            for barLine in barLines where spaces.contains(barLine.space) {
                let x = labelWidth + CGFloat(barLine.space - spaces.lowerBound) * columnWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 16))
                path.addLine(
                    to: CGPoint(
                        x: x,
                        y: CGFloat(track.stringCount - 1) * lineHeight + 32
                    )
                )
                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.8)),
                    lineWidth: barLine.isDouble ? 3 : 1.5
                )
            }

            for space in spaces {
                guard let event = eventMap[space] else { continue }
                let x = labelWidth + CGFloat(space - spaces.lowerBound) * columnWidth + columnWidth / 2

                for note in event.notes {
                    let line = track.stringCount - note.string - 1
                    let y = CGFloat(line) * lineHeight + 24
                    let label: String
                    switch note.value {
                    case let .fret(fret): label = String(fret)
                    case .muted: label = "x"
                    case .stopped: label = "*"
                    }

                    let text = Text(label)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                    let textSize = context.resolve(text).measure(in: size)
                    let rect = CGRect(
                        x: x - textSize.width / 2 - 2,
                        y: y - textSize.height / 2 - 1,
                        width: textSize.width + 4,
                        height: textSize.height + 2
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 3),
                        with: .color(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    context.draw(text, at: CGPoint(x: x, y: y))
                }
            }

            context.draw(
                Text("\(spaces.lowerBound + 1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary),
                at: CGPoint(x: labelWidth + 2, y: 7),
                anchor: .leading
            )
        }
        .frame(
            width: labelWidth + CGFloat(spaces.count) * columnWidth + 10,
            height: CGFloat(track.stringCount) * lineHeight + 30
        )
        .padding(8)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal)
    }

    private func tuningLabel(for string: Int) -> String {
        guard !track.isDrumTrack else { return String(string + 1) }
        let standard = [40, 45, 50, 55, 59, 64, 0, 0]
        guard standard.indices.contains(string), track.tuning.indices.contains(string) else {
            return "?"
        }
        let midi = standard[string] + track.tuning[string] + track.transpose
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return names[(midi % 12 + 12) % 12]
    }
}

private struct SongInfoView: View {
    let song: LoadedSong

    var body: some View {
        List {
            Section("Song") {
                if !song.score.title.isEmpty {
                    LabeledContent("Title", value: song.score.title)
                }
                if !song.score.artist.isEmpty {
                    LabeledContent("Artist", value: song.score.artist)
                }
                if !song.score.album.isEmpty {
                    LabeledContent("Album", value: song.score.album)
                }
                LabeledContent("Tempo", value: "\(song.score.tempo) BPM")
                LabeledContent("Tracks", value: song.score.tracks.count.formatted())
            }

            Section("File") {
                LabeledContent("Format", value: song.summary.formatIdentifier)
                LabeledContent("Version", value: song.summary.version)
                LabeledContent(
                    "Size",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(song.summary.fileLength),
                        countStyle: .file
                    )
                )
            }

            if !song.score.comment.isEmpty {
                Section("Comments & Lyrics") {
                    Text(song.score.comment)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private extension UTType {
    static let tabitTablature = UTType(importedAs: "com.jbegeman.tabit.tablature")
}

#Preview {
    ContentView()
}
