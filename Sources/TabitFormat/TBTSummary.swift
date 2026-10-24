import Foundation

public struct TBTPayloadSummary: Equatable, Identifiable, Sendable {
    public let index: Int
    public let compressedOffset: Int
    public let compressedLength: Int
    public let decompressedLength: Int

    public var id: Int { index }
}

public struct TBTSummary: Equatable, Sendable {
    public let fileName: String
    public let title: String
    public let formatIdentifier: String
    public let version: String
    public let fileLength: Int
    public let payloads: [TBTPayloadSummary]
    public let recoveredText: [String]

    public init(document: TBTDocument, fileName: String) {
        let recoveredText = document.payloads.first?
            .printableStrings
            .filter(Self.isLikelyReadableText) ?? []

        self.fileName = fileName
        self.title = recoveredText.first ?? fileName
        self.formatIdentifier = "TBT" + Self.markerString(document.header.formatMarker)
        self.version = document.header.version
        self.fileLength = document.originalData.count
        self.payloads = document.payloads.enumerated().map { index, payload in
            TBTPayloadSummary(
                index: index,
                compressedOffset: payload.compressedRange.lowerBound,
                compressedLength: payload.compressedRange.count,
                decompressedLength: payload.data.count
            )
        }
        self.recoveredText = recoveredText
    }

    private static func markerString(_ marker: UInt8) -> String {
        guard marker >= 0x20, marker <= 0x7e else { return "?" }
        return String(UnicodeScalar(marker))
    }

    private static func isLikelyReadableText(_ value: String) -> Bool {
        let alphanumericCount = value.unicodeScalars.count {
            CharacterSet.alphanumerics.contains($0)
        }
        return alphanumericCount >= max(3, value.count / 2)
    }
}
