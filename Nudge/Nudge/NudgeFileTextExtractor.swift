//
//  NudgeFileTextExtractor.swift
//  Nudge
//
//  Created by Codex on 6/18/26.
//

import Foundation
import zlib

enum NudgeOfficeDocumentKind {
    case word
    case powerPoint
    case excel
}

struct NudgeExtractedFileText {
    let text: String
    let isTruncated: Bool
}

enum NudgeFileTextExtractionError: LocalizedError {
    case unreadableText
    case unreadableArchive
    case unsupportedCompression

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            "파일 내용을 읽을 수 없습니다."
        case .unreadableArchive:
            "Office 문서 내용을 읽을 수 없습니다."
        case .unsupportedCompression:
            "지원하지 않는 Office 문서 압축 형식입니다."
        }
    }
}

enum NudgeFileTextExtractor {
    static let perFileCharacterLimit = 120_000

    static func extractPlainText(from url: URL, limit: Int = perFileCharacterLimit) throws -> NudgeExtractedFileText {
        let data = try Data(contentsOf: url)

        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? String(data: data, encoding: .utf16BigEndian)
            ?? String(data: data, encoding: .isoLatin1)

        guard let text else {
            throw NudgeFileTextExtractionError.unreadableText
        }

        return limited(text, limit: limit)
    }

    static func extractOfficeText(
        from url: URL,
        kind: NudgeOfficeDocumentKind,
        limit: Int = perFileCharacterLimit
    ) throws -> NudgeExtractedFileText {
        let archive = try NudgeZipArchive(data: Data(contentsOf: url))
        let entryNames = archive.entryNames
            .filter { entryName in
                switch kind {
                case .word:
                    entryName == "word/document.xml"
                case .powerPoint:
                    entryName.hasPrefix("ppt/slides/") && entryName.hasSuffix(".xml")
                case .excel:
                    entryName == "xl/sharedStrings.xml" || (entryName.hasPrefix("xl/worksheets/") && entryName.hasSuffix(".xml"))
                }
            }
            .sorted()

        let extractedText = try entryNames.compactMap { entryName -> String? in
            guard let data = try archive.data(for: entryName),
                  let xml = String(data: data, encoding: .utf8) else {
                return nil
            }

            return plainText(fromXML: xml)
        }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !extractedText.isEmpty else {
            throw NudgeFileTextExtractionError.unreadableArchive
        }

        return limited(extractedText, limit: limit)
    }

    private static func limited(_ text: String, limit: Int) -> NudgeExtractedFileText {
        guard text.count > limit else {
            return NudgeExtractedFileText(text: text, isTruncated: false)
        }

        return NudgeExtractedFileText(text: String(text.prefix(limit)), isTruncated: true)
    }

    private static func plainText(fromXML xml: String) -> String {
        let withoutTags = xml
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")

        return withoutTags
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct NudgeZipArchive {
    private struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    let data: Data
    private let entriesByName: [String: Entry]

    var entryNames: [String] {
        Array(entriesByName.keys)
    }

    init(data: Data) throws {
        self.data = data
        self.entriesByName = try Self.readEntries(from: data)
    }

    func data(for name: String) throws -> Data? {
        guard let entry = entriesByName[name] else { return nil }
        let localHeaderOffset = entry.localHeaderOffset

        guard data.count >= localHeaderOffset + 30,
              entry.compressedSize >= 0,
              entry.uncompressedSize >= 0 else {
            throw NudgeFileTextExtractionError.unreadableArchive
        }

        guard data.uint32(at: localHeaderOffset) == 0x0403_4B50 else {
            throw NudgeFileTextExtractionError.unreadableArchive
        }

        let fileNameLength = Int(data.uint16(at: localHeaderOffset + 26))
        let extraFieldLength = Int(data.uint16(at: localHeaderOffset + 28))
        let compressedDataOffset = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        guard compressedDataOffset >= 0,
              data.count >= compressedDataOffset + entry.compressedSize else {
            throw NudgeFileTextExtractionError.unreadableArchive
        }

        let compressedData = data.subdata(in: compressedDataOffset..<(compressedDataOffset + entry.compressedSize))

        switch entry.compressionMethod {
        case 0:
            return compressedData
        case 8:
            return try compressedData.inflatedRawDeflate(expectedSize: entry.uncompressedSize)
        default:
            throw NudgeFileTextExtractionError.unsupportedCompression
        }
    }

    private static func readEntries(from data: Data) throws -> [String: Entry] {
        guard let endRecordOffset = data.endOfCentralDirectoryOffset else {
            throw NudgeFileTextExtractionError.unreadableArchive
        }

        let entryCount = Int(data.uint16(at: endRecordOffset + 10))
        var centralDirectoryOffset = Int(data.uint32(at: endRecordOffset + 16))
        var entries: [String: Entry] = [:]

        for _ in 0..<entryCount {
            guard data.count >= centralDirectoryOffset + 46 else {
                throw NudgeFileTextExtractionError.unreadableArchive
            }

            guard data.uint32(at: centralDirectoryOffset) == 0x0201_4B50 else {
                throw NudgeFileTextExtractionError.unreadableArchive
            }

            let compressionMethod = data.uint16(at: centralDirectoryOffset + 10)
            let compressedSize = Int(data.uint32(at: centralDirectoryOffset + 20))
            let uncompressedSize = Int(data.uint32(at: centralDirectoryOffset + 24))
            let fileNameLength = Int(data.uint16(at: centralDirectoryOffset + 28))
            let extraFieldLength = Int(data.uint16(at: centralDirectoryOffset + 30))
            let fileCommentLength = Int(data.uint16(at: centralDirectoryOffset + 32))
            let localHeaderOffset = Int(data.uint32(at: centralDirectoryOffset + 42))
            let fileNameStart = centralDirectoryOffset + 46
            guard data.count >= fileNameStart + fileNameLength else {
                throw NudgeFileTextExtractionError.unreadableArchive
            }

            let fileNameData = data.subdata(in: fileNameStart..<(fileNameStart + fileNameLength))

            if let name = String(data: fileNameData, encoding: .utf8), !name.hasSuffix("/") {
                entries[name] = Entry(
                    name: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            }

            centralDirectoryOffset = fileNameStart + fileNameLength + extraFieldLength + fileCommentLength
            guard centralDirectoryOffset <= data.count else {
                throw NudgeFileTextExtractionError.unreadableArchive
            }
        }

        return entries
    }
}

private extension Data {
    var endOfCentralDirectoryOffset: Int? {
        let signature: UInt32 = 0x0605_4B50
        let searchLowerBound = Swift.max(0, count - 65_557)

        guard count >= 22 else { return nil }

        for offset in stride(from: count - 22, through: searchLowerBound, by: -1) {
            if uint32(at: offset) == signature {
                return offset
            }
        }

        return nil
    }

    func uint16(at offset: Int) -> UInt16 {
        withUnsafeBytes { bytes in
            let baseAddress = bytes.baseAddress!.advanced(by: offset)
            return baseAddress.loadUnaligned(as: UInt16.self).littleEndian
        }
    }

    func uint32(at offset: Int) -> UInt32 {
        withUnsafeBytes { bytes in
            let baseAddress = bytes.baseAddress!.advanced(by: offset)
            return baseAddress.loadUnaligned(as: UInt32.self).littleEndian
        }
    }

    func inflatedRawDeflate(expectedSize: Int) throws -> Data {
        var output = Data(count: expectedSize)
        var stream = z_stream()

        let initResult = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else {
            throw NudgeFileTextExtractionError.unreadableArchive
        }

        defer {
            inflateEnd(&stream)
        }

        try withUnsafeBytes { inputBuffer in
            try output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in = uInt(count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(expectedSize)

                let result = inflate(&stream, Z_FINISH)
                guard result == Z_STREAM_END else {
                    throw NudgeFileTextExtractionError.unreadableArchive
                }
            }
        }

        return output
    }
}
