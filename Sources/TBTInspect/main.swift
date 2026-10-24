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

    let path: String
    let fileLength: Int
    let version: String
    let declaredFileLength: Int
    let firstCompressedStreamLength: Int
    let payloads: [Payload]
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("Usage: tbt-inspect <file.tbt>\n".utf8)
    )
    exit(64)
}

let path = CommandLine.arguments[1]

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let document = try TBTDocument.parse(data)
    let inspection = Inspection(
        path: path,
        fileLength: data.count,
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
        }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(inspection), as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("tbt-inspect: \(error.localizedDescription)\n".utf8))
    exit(65)
}
