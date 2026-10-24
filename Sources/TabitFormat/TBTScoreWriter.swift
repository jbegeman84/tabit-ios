import CTabitCompression
import Foundation

public enum TBTScoreWriter {
    /// Saves note, mute, stop, and per-string effect edits while preserving
    /// metadata, bar lines, timing regions, and track effects byte-for-byte.
    public static func serialize(
        document: TBTDocument,
        score: TBTScore
    ) throws -> Data {
        let version = document.header.formatMarker
        guard (0x6f...0x72).contains(version) else {
            throw TBTError.unsupportedScoreVersion(marker: version)
        }
        guard score.tracks.count == document.header.trackCount,
              document.payloads.count == 2 else {
            throw TBTError.malformedScore("track count changed")
        }

        let originalBody = document.payloads[1].data
        let noteSections = try locateNoteSections(
            body: originalBody,
            header: document.header,
            tracks: score.tracks
        )
        guard let firstSection = noteSections.first,
              let lastSection = noteSections.last else {
            throw TBTError.malformedScore("missing note sections")
        }

        var rebuiltBody = originalBody.subdata(in: 0..<firstSection.range.lowerBound)
        for (index, section) in noteSections.enumerated() {
            var slots = section.expanded
            let track = score.tracks[index]

            for space in 0..<track.spaceCount {
                for string in 0..<track.stringCount {
                    slots[space * 20 + string] = 0
                    slots[space * 20 + 8 + string] = 0
                }
            }

            for event in track.events where event.space >= 0 && event.space < track.spaceCount {
                for note in event.notes where note.string >= 0 && note.string < track.stringCount {
                    let base = event.space * 20
                    switch note.value {
                    case let .fret(fret):
                        guard (0...99).contains(fret) else {
                            throw TBTError.malformedScore("fret \(fret) is out of range")
                        }
                        slots[base + note.string] = UInt8(0x80 + fret)
                    case .muted:
                        slots[base + note.string] = 0x11
                    case .stopped:
                        slots[base + note.string] = 0x12
                    }
                    slots[base + 8 + note.string] = note.effect?.rawValue ?? 0
                }
            }
            rebuiltBody.append(encodeDeltaList(slots))
        }
        rebuiltBody.append(originalBody.subdata(in: lastSection.range.upperBound..<originalBody.count))

        let compressedBody = try deflate(rebuiltBody)
        let compressedMetadata = document.originalData.subdata(
            in: document.payloads[0].compressedRange
        )

        var header = document.header.rawData
        var result = header
        result.append(compressedMetadata)
        result.append(compressedBody)

        header.writeLittleEndianUInt32(crc32(result.subdata(in: 64..<result.count)), at: 0x34)
        header.writeLittleEndianUInt32(UInt32(result.count), at: 0x38)
        header.writeLittleEndianUInt32(crc32(header.prefix(60)), at: 0x3c)
        result.replaceSubrange(0..<64, with: header)
        return result
    }

    private struct NoteSection {
        let range: Range<Int>
        let expanded: [UInt8]
    }

    private static func locateNoteSections(
        body: Data,
        header: TBTHeader,
        tracks: [TBTTrack]
    ) throws -> [NoteSection] {
        var reader = WriterCursor(body)
        if header.formatMarker >= 0x70 {
            try reader.skip(header.barCount * 6)
        } else {
            _ = try reader.readExpandedDeltaList(expectedCount: header.spaceCount)
        }

        var sections: [NoteSection] = []
        for track in tracks {
            let start = reader.offset
            let expanded = try reader.readExpandedDeltaList(expectedCount: track.spaceCount * 20)
            sections.append(NoteSection(range: start..<reader.offset, expanded: expanded))
        }
        return sections
    }

    private static func encodeDeltaList(_ values: [UInt8]) -> Data {
        struct Token {
            let bytes: [UInt8]
            let pairCount: Int
        }

        var tokens: [Token] = []
        var index = 0
        while index < values.count {
            let value = values[index]
            var runLength = 1
            while index + runLength < values.count,
                  values[index + runLength] == value,
                  runLength < 65_535 {
                runLength += 1
            }

            if runLength <= 255 {
                tokens.append(Token(bytes: [UInt8(runLength), value], pairCount: 1))
            } else {
                tokens.append(
                    Token(
                        bytes: [
                            0,
                            UInt8(runLength & 0xff),
                            UInt8((runLength >> 8) & 0xff),
                            value,
                        ],
                        pairCount: 2
                    )
                )
            }
            index += runLength
        }

        var result = Data()
        var chunkBytes: [UInt8] = []
        var chunkPairs = 0

        func appendChunk() {
            guard chunkPairs > 0 else { return }
            result.append(UInt8(chunkPairs & 0xff))
            result.append(UInt8((chunkPairs >> 8) & 0xff))
            result.append(contentsOf: chunkBytes)
        }

        for token in tokens {
            if chunkPairs + token.pairCount > 0x1000 {
                appendChunk()
                chunkBytes.removeAll(keepingCapacity: true)
                chunkPairs = 0
            }
            chunkBytes.append(contentsOf: token.bytes)
            chunkPairs += token.pairCount
        }
        appendChunk()
        return result
    }

    private static func deflate(_ data: Data) throws -> Data {
        try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw TBTError.malformedScore("cannot compress an empty body")
            }
            var output: UnsafeMutablePointer<UInt8>?
            var outputLength = 0
            let status = tabit_deflate_zlib(input, data.count, &output, &outputLength)
            guard status == 0, let output else {
                throw TBTError.invalidCompressedStream(offset: 64, status: status)
            }
            defer { tabit_free(output) }
            return Data(bytes: output, count: outputLength)
        }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return tabit_crc32(base, data.count)
        }
    }
}

private struct WriterCursor {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else {
            throw TBTError.malformedScore("invalid byte count \(count) at offset \(offset)")
        }
        offset += count
    }

    mutating func readExpandedDeltaList(expectedCount: Int) throws -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(expectedCount)

        while result.count < expectedCount {
            guard offset + 2 <= bytes.count else {
                throw TBTError.malformedScore("truncated delta-list chunk")
            }
            let pairCount = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2
            guard pairCount <= 0x1000, offset + pairCount * 2 <= bytes.count else {
                throw TBTError.malformedScore("invalid delta-list chunk")
            }

            let end = offset + pairCount * 2
            while offset < end {
                let increment: Int
                let value: UInt8
                if bytes[offset] == 0 {
                    guard offset + 3 < end else {
                        throw TBTError.malformedScore("truncated long delta")
                    }
                    increment = Int(bytes[offset + 1]) | (Int(bytes[offset + 2]) << 8)
                    value = bytes[offset + 3]
                    offset += 4
                } else {
                    increment = Int(bytes[offset])
                    value = bytes[offset + 1]
                    offset += 2
                }
                result.append(contentsOf: repeatElement(value, count: increment))
            }
        }

        guard result.count == expectedCount else {
            throw TBTError.malformedScore("expanded delta-list size mismatch")
        }
        return result
    }
}

private extension Data {
    mutating func writeLittleEndianUInt32(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}
