import Foundation
import TabitFormat

struct Inspection: Encodable {
    struct Payload: Encodable {
        let index: Int
        let compressedOffset: Int
        let compressedLength: Int
        let decompressedLength: Int
        let printableStrings: [String]
    }

    struct Track: Encodable {
        let index: Int
        let instrument: String
        let stringCount: Int
        let spaceCount: Int
        let eventCount: Int
        let noteChecksum: String
    }

    let path: String
    let fileLength: Int
    let formatMarker: Int
    let version: String
    let declaredFileLength: Int
    let firstCompressedStreamLength: Int
    let payloads: [Payload]
    let title: String
    let artist: String
    let tempo: Int
    let tracks: [Track]
}

let arguments = Array(CommandLine.arguments.dropFirst())
let path: String
let roundTripOutputPath: String?

if arguments.count == 1 {
    path = arguments[0]
    roundTripOutputPath = nil
} else if arguments.count == 3, arguments[0] == "--round-trip" {
    path = arguments[1]
    roundTripOutputPath = arguments[2]
} else {
    FileHandle.standardError.write(
        Data(
            """
            Usage:
              tbt-inspect <file.tbt>
              tbt-inspect --round-trip <input.tbt> <output.tbt>

            """.utf8
        )
    )
    exit(64)
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let document = try TBTDocument.parse(data)
    let score = try TBTScoreParser.parse(document)
    if let roundTripOutputPath {
        let savedData = try TBTScoreWriter.serialize(document: document, score: score)
        try savedData.write(to: URL(fileURLWithPath: roundTripOutputPath), options: .atomic)
        let reparsed = try TBTDocument.parse(savedData)
        _ = try TBTScoreParser.parse(reparsed)
    }
    let inspection = Inspection(
        path: path,
        fileLength: data.count,
        formatMarker: Int(document.header.formatMarker),
        version: document.header.version,
        declaredFileLength: document.header.declaredFileLength,
        firstCompressedStreamLength: document.header.firstCompressedStreamLength,
        payloads: document.payloads.enumerated().map { index, payload in
            Inspection.Payload(
                index: index,
                compressedOffset: payload.compressedRange.lowerBound,
                compressedLength: payload.compressedRange.count,
                decompressedLength: payload.data.count,
                printableStrings: Array(payload.printableStrings.prefix(40))
            )
        },
        title: score.title,
        artist: score.artist,
        tempo: score.tempo,
        tracks: score.tracks.map { track in
            Inspection.Track(
                index: track.id,
                instrument: track.instrumentName,
                stringCount: track.stringCount,
                spaceCount: track.spaceCount,
                eventCount: track.events.count,
                noteChecksum: noteChecksum(track)
            )
        }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(inspection), as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("tbt-inspect: \(error.localizedDescription)\n".utf8))
    exit(65)
}

private func noteChecksum(_ track: TBTTrack) -> String {
    var hash: UInt64 = 0xcbf29ce484222325

    func add(_ byte: UInt8) {
        hash ^= UInt64(byte)
        hash &*= 0x100000001b3
    }

    func add(_ value: Int) {
        var bits = UInt64(bitPattern: Int64(value))
        for _ in 0..<8 {
            add(UInt8(bits & 0xff))
            bits >>= 8
        }
    }

    for event in track.events {
        add(event.space)
        add(event.notes.count)
        for note in event.notes {
            add(note.string)
            switch note.value {
            case let .fret(fret):
                add(1)
                add(fret)
            case .muted:
                add(2)
            case .stopped:
                add(3)
            }
            add(Int(note.effect?.rawValue ?? 0))
        }
        add(Int(event.topText?.unicodeScalars.first?.value ?? 0))
        add(Int(event.bottomText?.unicodeScalars.first?.value ?? 0))
    }
    return String(format: "%016llx", hash)
}
