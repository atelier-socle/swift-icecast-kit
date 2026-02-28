// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ICYMetadataEncoder")
struct ICYMetadataEncoderTests {

    let encoder = ICYMetadataEncoder()

    // MARK: - encodeEmpty

    @Test("Empty metadata → single 0x00 byte")
    func encodeEmptyByte() {
        let data = encoder.encodeEmpty()
        #expect(data == Data([0x00]))
        #expect(data.count == 1)
    }

    // MARK: - encode (binary format)

    @Test("StreamTitle only → correct binary format")
    func encodeStreamTitleOnly() throws {
        let metadata = ICYMetadata(streamTitle: "Test Song")
        let data = try encoder.encode(metadata)

        #expect(data[0] > 0)
        let n = Int(data[0])
        #expect(data.count == 1 + n * 16)
    }

    @Test("First byte is correct N value")
    func encodeCorrectN() throws {
        let metadata = ICYMetadata(streamTitle: "Hi")
        let data = try encoder.encode(metadata)

        let metaString = encoder.encodeString(metadata)
        let byteLength = Data(metaString.utf8).count
        let expectedN = (byteLength + 15) / 16

        #expect(Int(data[0]) == expectedN)
    }

    @Test("Total size is 1 + N × 16")
    func encodeTotalSize() throws {
        let metadata = ICYMetadata(streamTitle: "Artist - Song Title")
        let data = try encoder.encode(metadata)

        let n = Int(data[0])
        #expect(data.count == 1 + n * 16)
    }

    @Test("Padding bytes are all 0x00")
    func encodePaddingZeros() throws {
        let metadata = ICYMetadata(streamTitle: "Hi")
        let data = try encoder.encode(metadata)

        let metaString = encoder.encodeString(metadata)
        let byteLength = Data(metaString.utf8).count
        let n = Int(data[0])
        let paddedLength = n * 16

        // Check padding bytes after the metadata string
        for i in (1 + byteLength)..<(1 + paddedLength) {
            #expect(data[i] == 0x00)
        }
    }

    @Test("Metadata string starts at byte 1")
    func encodeStringAtByte1() throws {
        let metadata = ICYMetadata(streamTitle: "Song")
        let data = try encoder.encode(metadata)

        let expected = encoder.encodeString(metadata)
        let expectedBytes = Data(expected.utf8)
        let actualBytes = data.subdata(in: 1..<(1 + expectedBytes.count))

        #expect(actualBytes == expectedBytes)
    }

    @Test("StreamTitle + StreamUrl → both present in output")
    func encodeBothFields() throws {
        let metadata = ICYMetadata(streamTitle: "Song", streamUrl: "http://x.com")
        let data = try encoder.encode(metadata)

        let n = Int(data[0])
        let payload = data.subdata(in: 1..<(1 + n * 16))
        let payloadString = String(decoding: payload, as: UTF8.self)

        #expect(payloadString.contains("StreamTitle='Song';"))
        #expect(payloadString.contains("StreamUrl='http://x.com';"))
    }

    @Test("Custom fields included in output")
    func encodeCustomFields() throws {
        let metadata = ICYMetadata(customFields: ["CustomKey": "CustomVal"])
        let data = try encoder.encode(metadata)

        let n = Int(data[0])
        let payload = data.subdata(in: 1..<(1 + n * 16))
        let payloadString = String(decoding: payload, as: UTF8.self)

        #expect(payloadString.contains("CustomKey='CustomVal';"))
    }

    // MARK: - Field ordering

    @Test("Field order: StreamTitle, StreamUrl, then custom alphabetical")
    func encodeFieldOrdering() {
        let metadata = ICYMetadata(
            streamTitle: "Song",
            streamUrl: "http://x.com",
            customFields: ["Zebra": "z", "Alpha": "a"]
        )
        let result = encoder.encodeString(metadata)

        guard let titleRange = result.range(of: "StreamTitle="),
            let urlRange = result.range(of: "StreamUrl="),
            let alphaRange = result.range(of: "Alpha="),
            let zebraRange = result.range(of: "Zebra=")
        else {
            Issue.record("Expected all fields to be present in: \(result)")
            return
        }

        #expect(titleRange.lowerBound < urlRange.lowerBound)
        #expect(urlRange.lowerBound < alphaRange.lowerBound)
        #expect(alphaRange.lowerBound < zebraRange.lowerBound)
    }

    // MARK: - Escaping

    @Test("Single quotes in values are backslash-escaped")
    func escapeSingleQuotes() {
        let metadata = ICYMetadata(streamTitle: "It's a test")
        let result = encoder.encodeString(metadata)
        #expect(result.contains("It\\'s a test"))
    }

    @Test("Backslash in values is preserved")
    func escapeBackslash() {
        let metadata = ICYMetadata(streamTitle: "path\\file")
        let result = encoder.encodeString(metadata)
        #expect(result.contains("path\\file"))
    }

    // MARK: - Edge cases

    @Test("Exactly 16 bytes of metadata (N=1, no padding)")
    func encodeExactly16Bytes() throws {
        // Build a metadata string that is exactly 16 bytes
        // StreamTitle='X'; = 16 bytes → S t r e a m T i t l e = ' X ' ;
        let metadata = ICYMetadata(streamTitle: "X")
        let metaStr = encoder.encodeString(metadata)
        let byteLen = Data(metaStr.utf8).count

        let data = try encoder.encode(metadata)
        let n = Int(data[0])
        let expectedN = (byteLen + 15) / 16

        #expect(n == expectedN)
        #expect(data.count == 1 + n * 16)
    }

    @Test("Metadata needing rounding up (e.g., 17 bytes → N=2)")
    func encodeRoundingUp() throws {
        let metadata = ICYMetadata(streamTitle: "AB")
        let metaStr = encoder.encodeString(metadata)
        let byteLen = Data(metaStr.utf8).count

        let data = try encoder.encode(metadata)
        let n = Int(data[0])

        #expect(n == (byteLen + 15) / 16)
        #expect(data.count == 1 + n * 16)
    }

    @Test("Over maximum length throws metadataTooLong")
    func encodeOverMaximum() throws {
        let longTitle = String(repeating: "A", count: 4080)
        let metadata = ICYMetadata(streamTitle: longTitle)

        #expect(throws: IcecastError.self) {
            try encoder.encode(metadata)
        }
    }

    @Test("Unicode metadata (CJK characters)")
    func encodeUnicode() throws {
        let metadata = ICYMetadata(streamTitle: "\u{4F60}\u{597D}\u{4E16}\u{754C}")
        let data = try encoder.encode(metadata)

        #expect(data[0] > 0)
        let n = Int(data[0])
        #expect(data.count == 1 + n * 16)
    }

    @Test("Empty string values produce valid output")
    func encodeEmptyStringValues() throws {
        let metadata = ICYMetadata(streamTitle: "")
        let result = encoder.encodeString(metadata)
        #expect(result == "StreamTitle='';")

        let data = try encoder.encode(metadata)
        #expect(data[0] > 0)
    }

    // MARK: - encodeString

    @Test("Correct key='value'; format")
    func encodeStringFormat() {
        let metadata = ICYMetadata(streamTitle: "Song")
        let result = encoder.encodeString(metadata)
        #expect(result == "StreamTitle='Song';")
    }

    @Test("Multiple fields separated correctly")
    func encodeStringMultiple() {
        let metadata = ICYMetadata(streamTitle: "Song", streamUrl: "http://x.com")
        let result = encoder.encodeString(metadata)
        #expect(result == "StreamTitle='Song';StreamUrl='http://x.com';")
    }

    @Test("Empty metadata produces empty string")
    func encodeStringEmpty() {
        let metadata = ICYMetadata()
        let result = encoder.encodeString(metadata)
        #expect(result == "")
    }

    @Test("Empty metadata encodes to single zero byte")
    func encodeEmptyMetadata() throws {
        let metadata = ICYMetadata()
        let data = try encoder.encode(metadata)
        #expect(data == Data([0x00]))
    }
}
