import Foundation
import Testing
@testable import TabitFormat

struct TBTDocumentTests {
    private let fixture = Data(base64Encoded: "VEJUcrgHAzIuMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgAAAAAAAACBAAAAAAAAAHjaY2EISS0uYWNwLCrJLC4BABl0BCJ42mNgZGJmYWVj5+Dk4ubh5eMXEBQSFhEVE5eQlJKWkZWTZ6BQHgD6UAXR")!
    private let editableFixture = Data(base64Encoded: "VEJUcngBAzIuMAALAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAHgAQwAAAInYnqqVAAAA3bSSYXjaY2FgYGCTZkhggAAHCYb/DAjAyRCSWlyiEJyfl87G4FhUkllcwsrgmJNUmgvklpZk5BexMzjn5+am5pUAAH8RDwN42mNhAAEmBsZmfzALAAXbANo=")!

    @Test func parsesHeaderAndConcatenatedPayloads() throws {
        let document = try TBTDocument.parse(fixture)

        #expect(document.header.formatMarker == 0x72)
        #expect(document.header.version == "2.0")
        #expect(document.header.declaredFileLength == 129)
        #expect(document.header.firstCompressedStreamLength == 22)
        #expect(document.payloads.count == 2)
        #expect(document.payloads[0].compressedRange == 64..<86)
        #expect(document.payloads[0].data == Data([4, 0]) + Data("Test".utf8) + Data([6, 0]) + Data("Artist".utf8))
        #expect(document.payloads[1].data == Data(Array(0..<32) + Array(0..<32) + Array(0..<32)))
        #expect(document.originalData == fixture)
    }

    @Test func parsesLegacyFormatMarker() throws {
        var legacy = fixture
        legacy[3] = 0x6f
        legacy.replaceSubrange(7...9, with: Data("1.6".utf8))

        let document = try TBTDocument.parse(legacy)

        #expect(document.header.formatMarker == 0x6f)
        #expect(document.header.version == "1.6")
        #expect(document.payloads.count == 2)
    }

    @Test func extractsPrintableStringsConservatively() throws {
        let document = try TBTDocument.parse(fixture)

        #expect(document.payloads[0].printableStrings == ["Test", "Artist"])
        #expect(document.payloads[1].printableStrings.isEmpty)
    }

    @Test func createsAReadableSummary() throws {
        let document = try TBTDocument.parse(fixture)
        let summary = TBTSummary(document: document, fileName: "Example.tbt")

        #expect(summary.title == "Test")
        #expect(summary.fileName == "Example.tbt")
        #expect(summary.formatIdentifier == "TBTr")
        #expect(summary.version == "2.0")
        #expect(summary.fileLength == 129)
        #expect(summary.recoveredText == ["Test", "Artist"])
        #expect(summary.payloads.count == 2)
        #expect(summary.payloads[0].compressedLength == 22)
        #expect(summary.payloads[1].decompressedLength == 96)
    }

    @Test func decodesTrackMetadataAndNotes() throws {
        var metadata = Data([
            4, 0, 0, 0, // spaces
            6, // strings
            27, // clean-guitar MIDI program
            0, // muted-guitar program
            96, // volume
            0, // modulation
            0, 0, // pitch bend
            0, // transpose
            0, // MIDI bank
            0, // reverb
            0, // chorus
            64, // pan
            24, // highest note
            0, // display MIDI numbers
            0xff, // automatic MIDI channel
            0, // top text
            0, // bottom text
            0, 0, 0, 0, 0, 0, 0, 0, // tuning
            0, // drums
        ])
        for value in ["Test Song", "Artist", "Album", "Author", "Comment"] {
            metadata.append(UInt8(value.utf8.count))
            metadata.append(0)
            metadata.append(contentsOf: value.utf8)
        }

        let body = Data([
            4, 0, 0, 0, 0, 0, // one bar-line record
            2, 0, // two delta pairs
            1, 0x83, // fret 3 on string 0
            79, 0, // remaining note slots
            4, 0, // four alternate-time delta pairs
            2, 1, 1, 2, 1, 3, 4, 1, // space 1 advances by 2/3
            0, 0, 0, 0, // empty track-effect chunk
        ])
        let header = TBTHeader(
            formatMarker: 0x72,
            tempo: 120,
            trackCount: 1,
            version: "2.0",
            featureBitfield: 0x1b,
            barCount: 1,
            spaceCount: 0,
            lastNonEmptySpace: 0,
            firstCompressedStreamLength: 0,
            declaredFileLength: 0,
            rawData: Data(repeating: 0, count: 64)
        )
        let document = TBTDocument(
            header: header,
            payloads: [
                TBTPayload(compressedRange: 64..<64, data: metadata),
                TBTPayload(compressedRange: 64..<64, data: body),
            ],
            originalData: Data()
        )

        let score = try TBTScoreParser.parse(document)

        #expect(score.title == "Test Song")
        #expect(score.artist == "Artist")
        #expect(score.tempo == 120)
        #expect(score.tracks.count == 1)
        #expect(score.tracks[0].instrumentName == "Electric Guitar (clean)")
        #expect(score.tracks[0].stringCount == 6)
        #expect(score.tracks[0].events.count == 1)
        #expect(score.tracks[0].events[0].notes == [
            TBTStringNote(string: 0, value: .fret(3), effect: nil),
        ])
        #expect(score.tracks[0].timelinePositions == [0, 1, 1.0 + 2.0 / 3.0, 2.0 + 2.0 / 3.0])
    }

    @Test func editsAndRoundTripsANote() throws {
        let document = try TBTDocument.parse(editableFixture)
        var score = try TBTScoreParser.parse(document)
        score.tracks[0].events[0].notes[0].value = .fret(5)

        let savedData = try TBTScoreWriter.serialize(document: document, score: score)
        let savedDocument = try TBTDocument.parse(savedData)
        let savedScore = try TBTScoreParser.parse(savedDocument)

        #expect(savedScore.title == "Test Song")
        #expect(savedScore.tracks[0].events[0].notes[0].value == .fret(5))
        #expect(savedDocument.header.declaredFileLength == savedData.count)
    }

    @Test func identifiesGuitarProgramsThatNeedAmplifierDistortion() {
        #expect(!GeneralMIDI.usesDistortionEffect(forProgram: 28))
        #expect(GeneralMIDI.usesDistortionEffect(forProgram: 29))
        #expect(GeneralMIDI.usesDistortionEffect(forProgram: 30))
        #expect(!GeneralMIDI.usesDistortionEffect(forProgram: 31))
    }

    @Test func rejectsInvalidSignature() {
        var invalid = fixture
        invalid[0] = 0

        #expect(throws: TBTError.invalidSignature) {
            try TBTDocument.parse(invalid)
        }
    }

    @Test func rejectsIncorrectDeclaredFileLength() {
        var invalid = fixture
        invalid[0x38] = 128

        #expect(throws: TBTError.declaredSizeMismatch(declared: 128, actual: 129)) {
            try TBTDocument.parse(invalid)
        }
    }

    @Test func rejectsIncorrectFirstStreamLength() {
        var invalid = fixture
        invalid[0x30] = 21

        #expect(throws: TBTError.firstStreamLengthMismatch(declared: 21, actual: 22)) {
            try TBTDocument.parse(invalid)
        }
    }
}
