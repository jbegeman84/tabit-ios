import Foundation

/// Field layout adapted from Brenton Bostick's MIT-licensed TBT format work:
/// https://github.com/bostick/tabit-file-format
public enum TBTScoreParser {
    public static func parse(_ document: TBTDocument) throws -> TBTScore {
        let version = document.header.formatMarker
        guard (0x6f...0x72).contains(version) else {
            throw TBTError.unsupportedScoreVersion(marker: version)
        }
        guard document.payloads.count == 2 else {
            throw TBTError.malformedScore("expected metadata and body streams")
        }

        let metadata = try parseMetadata(
            document.payloads[0].data,
            version: version,
            trackCount: document.header.trackCount,
            fallbackSpaceCount: document.header.spaceCount
        )
        let body = try parseBody(
            document.payloads[1].data,
            version: version,
            featureBitfield: document.header.featureBitfield,
            barCount: document.header.barCount,
            tracks: metadata.tracks
        )

        var tracks = metadata.tracks
        for index in tracks.indices {
            tracks[index].events = body.events[index]
            tracks[index].timelinePositions = body.timelinePositions[index]
        }

        return TBTScore(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            transcribedBy: metadata.transcribedBy,
            comment: metadata.comment,
            tempo: document.header.tempo,
            tracks: tracks,
            barLines: body.barLines
        )
    }

    private struct ParsedMetadata {
        var title: String
        var artist: String
        var album: String
        var transcribedBy: String
        var comment: String
        var tracks: [TBTTrack]
    }

    private struct TrackBuilder {
        var spaceCount = 0
        var stringCount = 0
        var midiProgram = 0
        var volume = 0
        var pan = 64
        var transpose = 0
        var tuning: [Int] = []
        var midiChannel = -1
        var drums = false
    }

    private static func parseMetadata(
        _ data: Data,
        version: UInt8,
        trackCount: Int,
        fallbackSpaceCount: Int
    ) throws -> ParsedMetadata {
        guard trackCount > 0, trackCount <= 15 else {
            throw TBTError.malformedScore("invalid track count \(trackCount)")
        }

        var reader = ByteCursor(data)
        var tracks = Array(repeating: TrackBuilder(), count: trackCount)

        if version >= 0x70 {
            for index in tracks.indices {
                tracks[index].spaceCount = try reader.readInt32()
            }
        } else {
            for index in tracks.indices {
                tracks[index].spaceCount = fallbackSpaceCount
            }
        }

        for index in tracks.indices {
            tracks[index].stringCount = Int(try reader.readUInt8())
        }
        for index in tracks.indices {
            tracks[index].midiProgram = Int(try reader.readUInt8() & 0x7f)
        }
        try reader.skip(trackCount) // legacy muted-guitar program
        for index in tracks.indices {
            tracks[index].volume = Int(try reader.readUInt8())
        }

        if version >= 0x71 {
            try reader.skip(trackCount) // modulation
            try reader.skip(trackCount * 2) // pitch bend
        }

        for index in tracks.indices {
            tracks[index].transpose = Int(try reader.readInt8())
        }
        try reader.skip(trackCount) // MIDI bank
        try reader.skip(trackCount) // reverb
        try reader.skip(trackCount) // chorus

        for index in tracks.indices {
            tracks[index].pan = Int(try reader.readUInt8())
        }
        try reader.skip(trackCount) // highest note
        try reader.skip(trackCount) // display MIDI note numbers
        for index in tracks.indices {
            tracks[index].midiChannel = Int(try reader.readInt8())
        }
        try reader.skip(trackCount) // top-line text enabled
        try reader.skip(trackCount) // bottom-line text enabled

        for index in tracks.indices {
            tracks[index].tuning = try (0..<8).map { _ in Int(try reader.readInt8()) }
        }
        for index in tracks.indices {
            tracks[index].drums = try reader.readUInt8() != 0
        }

        let title = try reader.readPascal2String()
        let artist = try reader.readPascal2String()
        let album = try reader.readPascal2String()
        let transcribedBy = try reader.readPascal2String()
        let comment = try reader.readPascal2String()

        guard reader.isAtEnd else {
            throw TBTError.malformedScore("unexpected metadata bytes at offset \(reader.offset)")
        }

        let parsedTracks = tracks.enumerated().map { index, track in
            TBTTrack(
                id: index,
                name: "Track \(index + 1)",
                spaceCount: track.spaceCount,
                stringCount: track.stringCount,
                midiProgram: track.midiProgram,
                volume: track.volume,
                pan: track.pan,
                transpose: track.transpose,
                tuning: track.tuning,
                isDrumTrack: track.drums || track.midiChannel == 9,
                events: [],
                timelinePositions: (0..<track.spaceCount).map(Double.init)
            )
        }

        return ParsedMetadata(
            title: title,
            artist: artist,
            album: album,
            transcribedBy: transcribedBy,
            comment: comment,
            tracks: parsedTracks
        )
    }

    private static func parseBody(
        _ data: Data,
        version: UInt8,
        featureBitfield: UInt8,
        barCount: Int,
        tracks: [TBTTrack]
    ) throws -> (
        barLines: [TBTBarLine],
        events: [[TBTNoteEvent]],
        timelinePositions: [[Double]]
    ) {
        var reader = ByteCursor(data)
        let barLines: [TBTBarLine]

        if version >= 0x70 {
            var space = 0
            var parsed: [TBTBarLine] = []
            for _ in 0..<barCount {
                let increment = try reader.readInt32()
                let flags = try reader.readUInt8()
                let repeats = try reader.readUInt8()
                parsed.append(
                    TBTBarLine(
                        space: space,
                        isDouble: flags & 0x01 != 0,
                        opensRepeat: flags & 0x02 != 0,
                        closesRepeat: flags & 0x04 != 0,
                        repeatCount: Int(repeats)
                    )
                )
                space += increment
            }
            barLines = parsed
        } else {
            guard let spaceCount = tracks.first?.spaceCount else {
                throw TBTError.malformedScore("missing tracks")
            }
            let values = try reader.readExpandedDeltaList(expectedCount: spaceCount)
            barLines = values.enumerated().compactMap { space, value in
                guard value != 0 else { return nil }
                let kind = value & 0x0f
                return TBTBarLine(
                    space: kind == 3 ? space : space + 1,
                    isDouble: kind == 4,
                    opensRepeat: kind == 3,
                    closesRepeat: kind == 2,
                    repeatCount: Int(value >> 4)
                )
            }
        }

        var allEvents: [[TBTNoteEvent]] = []
        for track in tracks {
            let slots = try reader.readExpandedDeltaList(expectedCount: track.spaceCount * 20)
            var events: [TBTNoteEvent] = []

            for space in 0..<track.spaceCount {
                let base = space * 20
                var notes: [TBTStringNote] = []
                for string in 0..<track.stringCount {
                    let rawNote = slots[base + string]
                    let effect = TBTNoteEffect(rawValue: slots[base + 8 + string])
                    let value: TBTStringNote.Value?
                    if rawNote >= 0x80 {
                        value = .fret(Int(rawNote - 0x80))
                    } else if rawNote == 0x11 {
                        value = .muted
                    } else if rawNote == 0x12 {
                        value = .stopped
                    } else {
                        value = nil
                    }
                    if let value {
                        notes.append(TBTStringNote(string: string, value: value, effect: effect))
                    }
                }

                let topText = asciiCharacter(slots[base + 17])
                let bottomText = asciiCharacter(slots[base + 18])
                if !notes.isEmpty || topText != nil || bottomText != nil {
                    events.append(
                        TBTNoteEvent(
                            space: space,
                            notes: notes,
                            topText: topText,
                            bottomText: bottomText
                        )
                    )
                }
            }
            allEvents.append(events)
        }

        var timelinePositions = tracks.map { track in
            (0..<track.spaceCount).map(Double.init)
        }
        if featureBitfield & 0x10 != 0 {
            for (trackIndex, track) in tracks.enumerated() {
                let timing = try reader.readExpandedDeltaList(expectedCount: track.spaceCount * 2)
                var position = 0.0
                var positions: [Double] = []
                positions.reserveCapacity(track.spaceCount)
                for space in 0..<track.spaceCount {
                    positions.append(position)
                    let numerator = Int(timing[space * 2])
                    let denominator = Int(timing[space * 2 + 1])
                    position += denominator == 0
                        ? 1
                        : Double(numerator) / Double(denominator)
                }
                timelinePositions[trackIndex] = positions
            }
        }

        if version >= 0x71 {
            for _ in tracks {
                let byteCount = try reader.readInt32()
                try reader.skip(byteCount)
            }
        }

        guard reader.isAtEnd else {
            throw TBTError.malformedScore("unexpected body bytes at offset \(reader.offset)")
        }
        return (barLines, allEvents, timelinePositions)
    }

    private static func asciiCharacter(_ byte: UInt8) -> Character? {
        guard byte >= 0x20, byte <= 0x7e else { return nil }
        return Character(UnicodeScalar(byte))
    }
}

private struct ByteCursor {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < bytes.count else {
            throw TBTError.malformedScore("unexpected end of data at offset \(offset)")
        }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readInt8() throws -> Int8 {
        Int8(bitPattern: try readUInt8())
    }

    mutating func readUInt16() throws -> Int {
        let low = Int(try readUInt8())
        let high = Int(try readUInt8())
        return low | (high << 8)
    }

    mutating func readInt32() throws -> Int {
        let b0 = Int(try readUInt8())
        let b1 = Int(try readUInt8())
        let b2 = Int(try readUInt8())
        let b3 = Int(try readUInt8())
        let value = UInt32(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
        return Int(Int32(bitPattern: value))
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else {
            throw TBTError.malformedScore("invalid byte count \(count) at offset \(offset)")
        }
        offset += count
    }

    mutating func readPascal2String() throws -> String {
        let count = try readUInt16()
        guard offset + count <= bytes.count else {
            throw TBTError.malformedScore("invalid string length \(count) at offset \(offset)")
        }
        let value = String(bytes: bytes[offset..<(offset + count)], encoding: .isoLatin1) ?? ""
        offset += count
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func readExpandedDeltaList(expectedCount: Int) throws -> [UInt8] {
        guard expectedCount >= 0 else {
            throw TBTError.malformedScore("negative delta-list size")
        }

        var encoded: [UInt8] = []
        var expandedCount = 0
        while expandedCount < expectedCount {
            let pairCount = try readUInt16()
            guard pairCount <= 0x1000, offset + pairCount * 2 <= bytes.count else {
                throw TBTError.malformedScore("invalid delta-list chunk at offset \(offset)")
            }
            let chunk = Array(bytes[offset..<(offset + pairCount * 2)])
            offset += pairCount * 2
            encoded.append(contentsOf: chunk)
            expandedCount += try Self.deltaCount(chunk)
        }
        guard expandedCount == expectedCount else {
            throw TBTError.malformedScore(
                "delta list expands to \(expandedCount) bytes; expected \(expectedCount)"
            )
        }
        return try Self.expandDeltaList(encoded, expectedCount: expectedCount)
    }

    private static func deltaCount(_ encoded: [UInt8]) throws -> Int {
        var index = 0
        var count = 0
        while index < encoded.count {
            let first = encoded[index]
            if first == 0 {
                guard index + 3 < encoded.count else {
                    throw TBTError.malformedScore("truncated long delta")
                }
                count += Int(encoded[index + 1]) | (Int(encoded[index + 2]) << 8)
                index += 4
            } else {
                guard index + 1 < encoded.count else {
                    throw TBTError.malformedScore("truncated delta")
                }
                count += Int(first)
                index += 2
            }
        }
        return count
    }

    private static func expandDeltaList(
        _ encoded: [UInt8],
        expectedCount: Int
    ) throws -> [UInt8] {
        var index = 0
        var result: [UInt8] = []
        result.reserveCapacity(expectedCount)

        while index < encoded.count {
            let increment: Int
            let value: UInt8
            if encoded[index] == 0 {
                guard index + 3 < encoded.count else {
                    throw TBTError.malformedScore("truncated long delta")
                }
                increment = Int(encoded[index + 1]) | (Int(encoded[index + 2]) << 8)
                value = encoded[index + 3]
                index += 4
            } else {
                guard index + 1 < encoded.count else {
                    throw TBTError.malformedScore("truncated delta")
                }
                increment = Int(encoded[index])
                value = encoded[index + 1]
                index += 2
            }
            result.append(contentsOf: repeatElement(value, count: increment))
        }

        guard result.count == expectedCount else {
            throw TBTError.malformedScore("expanded delta-list size mismatch")
        }
        return result
    }
}
