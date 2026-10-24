import Foundation
import Testing
@testable import TabitFormat

struct TBTDocumentTests {
    private let fixture = Data(base64Encoded: "VEJUcrgHAzIuMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgAAAAAAAACBAAAAAAAAAHjaY2EISS0uYWNwLCrJLC4BABl0BCJ42mNgZGJmYWVj5+Dk4ubh5eMXEBQSFhEVE5eQlJKWkZWTZ6BQHgD6UAXR")!

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
