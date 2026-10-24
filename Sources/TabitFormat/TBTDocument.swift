import CTabitCompression
import Foundation

public enum TBTError: Error, Equatable, LocalizedError {
    case fileTooShort(actual: Int)
    case invalidSignature
    case declaredSizeMismatch(declared: Int, actual: Int)
    case invalidCompressedStream(offset: Int, status: Int32)
    case emptyCompressedStream(offset: Int)
    case firstStreamLengthMismatch(declared: Int, actual: Int)
    case unsupportedScoreVersion(marker: UInt8)
    case malformedScore(String)

    public var errorDescription: String? {
        switch self {
        case let .fileTooShort(actual):
            "A TBT file needs a 64-byte header; this file has \(actual) bytes."
        case .invalidSignature:
            "The file does not start with the TabIt signature prefix “TBT”."
        case let .declaredSizeMismatch(declared, actual):
            "The header declares \(declared) bytes, but the file contains \(actual)."
        case let .invalidCompressedStream(offset, status):
            "The zlib stream at byte \(offset) is invalid (zlib status \(status))."
        case let .emptyCompressedStream(offset):
            "The zlib stream at byte \(offset) consumed no data."
        case let .firstStreamLengthMismatch(declared, actual):
            "The header declares a \(declared)-byte first stream, but it occupies \(actual) bytes."
        case let .unsupportedScoreVersion(marker):
            "Score decoding does not yet support TBT format marker 0x\(String(marker, radix: 16))."
        case let .malformedScore(message):
            "The score data is malformed: \(message)"
        }
    }
}

public struct TBTHeader: Equatable, Sendable {
    public static let byteCount = 64
    public static let signaturePrefix = Data([0x54, 0x42, 0x54])

    public let formatMarker: UInt8
    public let tempo: Int
    public let trackCount: Int
    public let version: String
    public let featureBitfield: UInt8
    public let barCount: Int
    public let spaceCount: Int
    public let lastNonEmptySpace: Int
    public let firstCompressedStreamLength: Int
    public let declaredFileLength: Int
    public let rawData: Data
}

public struct TBTPayload: Equatable, Sendable {
    public let compressedRange: Range<Int>
    public let data: Data

    public var printableStrings: [String] {
        var results: [String] = []
        var bytes: [UInt8] = []

        func finishRun() {
            if bytes.count >= 4, let value = String(bytes: bytes, encoding: .isoLatin1) {
                results.append(value)
            }
            bytes.removeAll(keepingCapacity: true)
        }

        for byte in data {
            if (0x20...0x7e).contains(byte) {
                bytes.append(byte)
            } else {
                finishRun()
            }
        }
        finishRun()
        return results
    }
}

public struct TBTDocument: Equatable, Sendable {
    public let header: TBTHeader
    public let payloads: [TBTPayload]

    /// Original bytes are retained so unsupported fields can be preserved
    /// exactly while the format is still being recovered.
    public let originalData: Data

    public static func parse(_ data: Data) throws -> TBTDocument {
        guard data.count >= TBTHeader.byteCount else {
            throw TBTError.fileTooShort(actual: data.count)
        }
        guard data.prefix(3) == TBTHeader.signaturePrefix else {
            throw TBTError.invalidSignature
        }

        let declaredFileLength = data.littleEndianUInt32(at: 0x38)
        if declaredFileLength != 0, declaredFileLength != data.count {
            throw TBTError.declaredSizeMismatch(
                declared: declaredFileLength,
                actual: data.count
            )
        }

        let versionBytes = data[7..<min(16, data.count)].prefix { $0 != 0 }
        let version = String(bytes: versionBytes, encoding: .ascii) ?? ""
        let firstStreamLength = data.littleEndianUInt32(at: 0x30)
        let header = TBTHeader(
            formatMarker: data[3],
            tempo: data.littleEndianUInt16(at: 0x2e),
            trackCount: Int(data[5]),
            version: version,
            featureBitfield: data[0x0b],
            barCount: data.littleEndianUInt16(at: 0x28),
            spaceCount: data.littleEndianUInt16(at: 0x2a),
            lastNonEmptySpace: data.littleEndianUInt16(at: 0x2c),
            firstCompressedStreamLength: firstStreamLength,
            declaredFileLength: declaredFileLength,
            rawData: data.prefix(TBTHeader.byteCount)
        )

        var payloads: [TBTPayload] = []
        var offset = TBTHeader.byteCount
        while offset < data.count {
            let compressedData = data.subdata(in: offset..<data.count)
            let inflated = try inflateOneStream(compressedData, fileOffset: offset)
            guard inflated.consumed > 0 else {
                throw TBTError.emptyCompressedStream(offset: offset)
            }
            payloads.append(
                TBTPayload(
                    compressedRange: offset..<(offset + inflated.consumed),
                    data: inflated.data
                )
            )
            offset += inflated.consumed
        }

        if firstStreamLength != 0,
           let actual = payloads.first?.compressedRange.count,
           firstStreamLength != actual {
            throw TBTError.firstStreamLengthMismatch(
                declared: firstStreamLength,
                actual: actual
            )
        }

        return TBTDocument(header: header, payloads: payloads, originalData: data)
    }

    private static func inflateOneStream(
        _ compressedData: Data,
        fileOffset: Int
    ) throws -> (data: Data, consumed: Int) {
        try compressedData.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw TBTError.emptyCompressedStream(offset: fileOffset)
            }

            var output: UnsafeMutablePointer<UInt8>?
            var outputLength = 0
            var consumed = 0
            let status = tabit_inflate_zlib(
                input,
                compressedData.count,
                &output,
                &outputLength,
                &consumed
            )
            guard status == 0, let output else {
                throw TBTError.invalidCompressedStream(offset: fileOffset, status: status)
            }
            defer { tabit_free(output) }
            return (Data(bytes: output, count: outputLength), consumed)
        }
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> Int {
        Int(self[offset]) | (Int(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> Int {
        Int(self[offset])
            | (Int(self[offset + 1]) << 8)
            | (Int(self[offset + 2]) << 16)
            | (Int(self[offset + 3]) << 24)
    }
}
