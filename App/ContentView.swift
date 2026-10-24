import SwiftUI
import TabitFormat
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var summary: TBTSummary?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    SongSummaryView(summary: summary)
                } else {
                    EmptyLibraryView {
                        isImporting = true
                    }
                }
            }
            .navigationTitle("Tabit")
            .toolbar {
                if summary != nil {
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
            summary = TBTSummary(document: document, fileName: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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

private struct SongSummaryView: View {
    let summary: TBTSummary

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 68, height: 68)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))

                    VStack(spacing: 4) {
                        Text(summary.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(summary.fileName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityIdentifier("songHeader")
            }

            Section("File") {
                LabeledContent("Format", value: summary.formatIdentifier)
                LabeledContent("Version", value: summary.version)
                LabeledContent(
                    "Size",
                    value: ByteCountFormatter.string(
                        fromByteCount: Int64(summary.fileLength),
                        countStyle: .file
                    )
                )
            }

            Section("Data Streams") {
                ForEach(summary.payloads) { payload in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Stream \(payload.index + 1)")
                            .font(.headline)
                        Text(
                            "\(payload.compressedLength.formatted()) compressed bytes · "
                                + "\(payload.decompressedLength.formatted()) recovered bytes"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !summary.recoveredText.isEmpty {
                Section("Recovered Text") {
                    ForEach(Array(summary.recoveredText.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .accessibilityIdentifier("songSummaryList")
    }
}

private extension UTType {
    static let tabitTablature = UTType(importedAs: "com.jbegeman.tabit.tablature")
}

#Preview {
    ContentView()
}
