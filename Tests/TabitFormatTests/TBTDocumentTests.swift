import Foundation
import Testing
@testable import TabitFormat

struct TBTDocumentTests {
    private let fixture = Data(base64Encoded: "VEJUcrgHAzIuMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgAAAAAAAACBAAAAAAAAAHjaY2EISS0uYWNwLCrJLC4BABl0BCJ42mNgZGJmYWVj5+Dk4ubh5eMXEBQSFhEVE5eQlJKWkZWTZ6BQHgD6UAXR")!

    @Test func parsesHeaderAndConcatenatedPayloads() throws {
        let document = try TBTDocument.parse(fixture)

        #expect(document.header.version == "2.0")
        #expect(document.header.declaredFileLength == 129)
        #expect(document.header.firstCompressedStreamLength == 22)
        #expect(document.payloads.count == 2)
        #expect(document.payloads[0].compressedRange == 64..<86)
        #expect(document.payloads[0].data == Data([4, 0]) + Data("Test".utf8) + Data([6, 0]) + Data("Artist".utf8))
        #expect(document.payloads[1].data == Data(Array(0..<32) + Array(0..<32) + Array(0..<32)))
        #expect(document.originalData == fixture)
    }

    @Test func extractsPrintableStringsConservatively() throws {
        let document = try TBTDocument.parse(fixture)

        #expect(document.payloads[0].printableStrings == ["Test", "Artist"])
        #expect(document.payloads[1].printableStrings.isEmpty)
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
