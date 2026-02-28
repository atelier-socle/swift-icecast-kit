// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ICYMetadataDecoder")
struct ICYMetadataDecoderTests {

    let decoder = ICYMetadataDecoder()
    let encoder = ICYMetadataEncoder()

    // MARK: - Basic decoding

    @Test("N=0 → empty metadata, bytesConsumed=1")
    func decodeEmpty() throws {
        let data = Data([0x00])
        let (metadata, consumed) = try decoder.decode(from: data)

        #expect(metadata.isEmpty)
        #expect(consumed == 1)
    }

    @Test("Decode encoded StreamTitle → roundtrip matches")
    func decodeStreamTitle() throws {
        let original = ICYMetadata(streamTitle: "Artist - Song")
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)

        #expect(decoded.streamTitle == "Artist - Song")
    }

    @Test("Decode StreamTitle + StreamUrl → both fields populated")
    func decodeBothFields() throws {
        let original = ICYMetadata(streamTitle: "Song", streamUrl: "http://x.com")
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)

        #expect(decoded.streamTitle == "Song")
        #expect(decoded.streamUrl == "http://x.com")
    }

    @Test("Decode custom fields → in customFields dictionary")
    func decodeCustomFields() throws {
        let original = ICYMetadata(customFields: ["MyKey": "MyVal"])
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)

        #expect(decoded.customFields["MyKey"] == "MyVal")
    }

    @Test("bytesConsumed = 1 + N × 16")
    func decodeBytesConsumed() throws {
        let original = ICYMetadata(streamTitle: "Hello World")
        let encoded = try encoder.encode(original)
        let n = Int(encoded[0])

        let (_, consumed) = try decoder.decode(from: encoded)
        #expect(consumed == 1 + n * 16)
    }

    // MARK: - Roundtrip

    @Test("Simple title roundtrip")
    func roundtripSimple() throws {
        let original = ICYMetadata(streamTitle: "Artist - Song")
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)
        #expect(decoded.streamTitle == original.streamTitle)
    }

    @Test("Title + URL + custom roundtrip")
    func roundtripAllFields() throws {
        let original = ICYMetadata(
            streamTitle: "Song",
            streamUrl: "http://example.com",
            customFields: ["Key": "Value"]
        )
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)

        #expect(decoded.streamTitle == original.streamTitle)
        #expect(decoded.streamUrl == original.streamUrl)
        #expect(decoded.customFields == original.customFields)
    }

    @Test("Unicode metadata roundtrip")
    func roundtripUnicode() throws {
        let original = ICYMetadata(streamTitle: "\u{4F60}\u{597D}\u{4E16}\u{754C}")
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)
        #expect(decoded.streamTitle == original.streamTitle)
    }

    @Test("Escaped quotes roundtrip")
    func roundtripEscapedQuotes() throws {
        let original = ICYMetadata(streamTitle: "It's a test")
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)
        #expect(decoded.streamTitle == "It's a test")
    }

    @Test("Empty string values roundtrip")
    func roundtripEmptyString() throws {
        let original = ICYMetadata(streamTitle: "")
        let encoded = try encoder.encode(original)
        let (decoded, _) = try decoder.decode(from: encoded)
        #expect(decoded.streamTitle == "")
    }

    // MARK: - String parsing

    @Test("Standard format: StreamTitle='Artist - Song';")
    func parseStandard() {
        let result = decoder.parse(string: "StreamTitle='Artist - Song';")
        #expect(result.streamTitle == "Artist - Song")
    }

    @Test("Multiple fields: StreamTitle + StreamUrl")
    func parseMultiple() {
        let result = decoder.parse(string: "StreamTitle='Song';StreamUrl='http://x';")
        #expect(result.streamTitle == "Song")
        #expect(result.streamUrl == "http://x")
    }

    @Test("Escaped quotes: StreamTitle='It\\'s OK';")
    func parseEscapedQuotes() {
        let result = decoder.parse(string: "StreamTitle='It\\'s OK';")
        #expect(result.streamTitle == "It's OK")
    }

    @Test("Unknown keys → customFields")
    func parseUnknownKeys() {
        let result = decoder.parse(string: "CustomKey='value';")
        #expect(result.customFields["CustomKey"] == "value")
    }

    @Test("Empty string → empty ICYMetadata")
    func parseEmpty() {
        let result = decoder.parse(string: "")
        #expect(result.isEmpty)
    }

    @Test("Malformed: missing closing quote → graceful handling")
    func parseMalformedNoClose() {
        let result = decoder.parse(string: "StreamTitle='incomplete")
        #expect(result.streamTitle == "incomplete")
    }

    @Test("Malformed: missing semicolon → graceful handling")
    func parseMalformedNoSemicolon() {
        let result = decoder.parse(string: "StreamTitle='Song'")
        #expect(result.streamTitle == "Song")
    }

    // MARK: - Edge cases

    @Test("Data too short for declared N → throws error")
    func decodeTooShort() throws {
        // N=2 means we need 33 bytes total, but provide only 10
        var data = Data([2])
        data.append(contentsOf: [UInt8](repeating: 0x41, count: 9))

        #expect(throws: IcecastError.self) {
            try decoder.decode(from: data)
        }
    }

    @Test("Maximum N=255 → correct decoding")
    func decodeMaxN() throws {
        let title = String(repeating: "A", count: 3000)
        let original = ICYMetadata(streamTitle: title)
        let encoded = try encoder.encode(original)
        let (decoded, consumed) = try decoder.decode(from: encoded)

        #expect(decoded.streamTitle == title)
        let n = Int(encoded[0])
        #expect(consumed == 1 + n * 16)
    }

    @Test("Empty data throws error")
    func decodeEmptyData() throws {
        #expect(throws: IcecastError.self) {
            try decoder.decode(from: Data())
        }
    }

    @Test("Null bytes in padding are stripped")
    func decodePaddingStripped() throws {
        // Manually create: N=1, "StreamTitle='X';" + null padding
        let metaStr = "StreamTitle='X';"
        let bytes = Data(metaStr.utf8)
        var data = Data([1])
        data.append(bytes)
        let padding = 16 - bytes.count
        if padding > 0 {
            data.append(contentsOf: [UInt8](repeating: 0, count: padding))
        }

        let (decoded, consumed) = try decoder.decode(from: data)
        #expect(decoded.streamTitle == "X")
        #expect(consumed == 17)
    }
}
