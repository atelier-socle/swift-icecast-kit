// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - ICYStreamDemuxer Tests

@Suite("ICYStreamDemuxer")
struct ICYStreamDemuxerTests {

    @Test("nil metaint returns all bytes as audio, no metadata")
    func nilMetaintPassthrough() {
        var demuxer = ICYStreamDemuxer(metaint: nil)
        let input = Data(repeating: 0xFF, count: 100)
        let result = demuxer.feed(input)
        #expect(result.audioBytes == input)
        #expect(result.metadata == nil)
    }

    @Test("zero-length metadata block passes audio intact")
    func zeroLengthMetadata() {
        var demuxer = ICYStreamDemuxer(metaint: 8)
        var input = Data(repeating: 0xAA, count: 8)
        input.append(0x00)
        input.append(Data(repeating: 0xBB, count: 5))

        let result = demuxer.feed(input)
        let expectedAudio =
            Data(repeating: 0xAA, count: 8)
            + Data(repeating: 0xBB, count: 5)
        #expect(result.audioBytes == expectedAudio)
        #expect(result.metadata == nil)
    }

    @Test("metadata present: audio bytes correct and metadata parsed")
    func metadataPresent() {
        var demuxer = ICYStreamDemuxer(metaint: 4)
        var input = Data(repeating: 0xAA, count: 4)

        let metaString = "StreamTitle='Artist - Title';"
        var metaBlock = Data(metaString.utf8)
        let padLength = 16 - (metaBlock.count % 16)
        if padLength < 16 {
            metaBlock.append(Data(repeating: 0x00, count: padLength))
        }
        let lengthByte = UInt8(metaBlock.count / 16)
        input.append(lengthByte)
        input.append(metaBlock)
        input.append(Data(repeating: 0xBB, count: 3))

        let result = demuxer.feed(input)
        let expectedAudio =
            Data(repeating: 0xAA, count: 4)
            + Data(repeating: 0xBB, count: 3)
        #expect(result.audioBytes == expectedAudio)
        #expect(result.metadata?.streamTitle == "Artist - Title")
    }

    @Test("StreamTitle parsed correctly from metadata block")
    func streamTitleParsed() {
        var demuxer = ICYStreamDemuxer(metaint: 2)
        var input = Data(repeating: 0x11, count: 2)

        let metaString = "StreamTitle='Hello World';"
        var metaBlock = Data(metaString.utf8)
        let padLength = 16 - (metaBlock.count % 16)
        if padLength < 16 {
            metaBlock.append(Data(repeating: 0x00, count: padLength))
        }
        input.append(UInt8(metaBlock.count / 16))
        input.append(metaBlock)

        let result = demuxer.feed(input)
        #expect(result.metadata?.streamTitle == "Hello World")
    }

    @Test("metadata split across multiple feed calls")
    func metadataSplitAcrossCalls() {
        var demuxer = ICYStreamDemuxer(metaint: 4)

        let metaString = "StreamTitle='Split Test';"
        var metaBlock = Data(metaString.utf8)
        let padLength = 16 - (metaBlock.count % 16)
        if padLength < 16 {
            metaBlock.append(Data(repeating: 0x00, count: padLength))
        }
        let lengthByte = UInt8(metaBlock.count / 16)

        var chunk1 = Data(repeating: 0xAA, count: 4)
        chunk1.append(lengthByte)
        chunk1.append(metaBlock.prefix(5))

        let result1 = demuxer.feed(chunk1)
        #expect(result1.audioBytes == Data(repeating: 0xAA, count: 4))
        #expect(result1.metadata == nil)

        let chunk2 = Data(metaBlock.dropFirst(5))
        let result2 = demuxer.feed(chunk2)
        #expect(result2.metadata?.streamTitle == "Split Test")
    }

    @Test("metadata at exact chunk boundary")
    func metadataAtBoundary() {
        var demuxer = ICYStreamDemuxer(metaint: 4)

        let chunk1 = Data(repeating: 0xAA, count: 4)
        let result1 = demuxer.feed(chunk1)
        #expect(result1.audioBytes == chunk1)

        var chunk2 = Data([0x00])
        chunk2.append(Data(repeating: 0xBB, count: 4))
        let result2 = demuxer.feed(chunk2)
        let expectedAudio = Data(repeating: 0xBB, count: 4)
        #expect(result2.audioBytes == expectedAudio)
        #expect(result2.metadata == nil)
    }

    @Test("multiple metadata blocks in a single feed call")
    func multipleMetadataBlocks() {
        var demuxer = ICYStreamDemuxer(metaint: 2)

        let metaString1 = "StreamTitle='First';"
        var metaBlock1 = Data(metaString1.utf8)
        let pad1 = 16 - (metaBlock1.count % 16)
        if pad1 < 16 { metaBlock1.append(Data(repeating: 0x00, count: pad1)) }

        let metaString2 = "StreamTitle='Second';"
        var metaBlock2 = Data(metaString2.utf8)
        let pad2 = 16 - (metaBlock2.count % 16)
        if pad2 < 16 { metaBlock2.append(Data(repeating: 0x00, count: pad2)) }

        var input = Data(repeating: 0xAA, count: 2)
        input.append(UInt8(metaBlock1.count / 16))
        input.append(metaBlock1)
        input.append(Data(repeating: 0xBB, count: 2))
        input.append(UInt8(metaBlock2.count / 16))
        input.append(metaBlock2)
        input.append(Data(repeating: 0xCC, count: 1))

        let result = demuxer.feed(input)
        #expect(result.metadata?.streamTitle == "Second")
        let expectedAudio =
            Data(repeating: 0xAA, count: 2)
            + Data(repeating: 0xBB, count: 2)
            + Data(repeating: 0xCC, count: 1)
        #expect(result.audioBytes == expectedAudio)
    }

    @Test("empty metadata content returns nil metadata")
    func emptyMetadataContent() {
        var demuxer = ICYStreamDemuxer(metaint: 4)
        var input = Data(repeating: 0xAA, count: 4)
        input.append(0x01)
        input.append(Data(repeating: 0x00, count: 16))

        let result = demuxer.feed(input)
        #expect(result.metadata == nil)
    }

    @Test("audio byte count correct with metadata present")
    func audioByteCountWithMetadata() {
        var demuxer = ICYStreamDemuxer(metaint: 10)

        let metaString = "StreamTitle='Test';"
        var metaBlock = Data(metaString.utf8)
        let pad = 16 - (metaBlock.count % 16)
        if pad < 16 { metaBlock.append(Data(repeating: 0x00, count: pad)) }

        var input = Data(repeating: 0xAA, count: 10)
        input.append(UInt8(metaBlock.count / 16))
        input.append(metaBlock)
        input.append(Data(repeating: 0xBB, count: 5))

        let result = demuxer.feed(input)
        #expect(result.audioBytes.count == 15)
    }

    @Test("audio byte count correct without metadata")
    func audioByteCountWithoutMetadata() {
        var demuxer = ICYStreamDemuxer(metaint: 10)

        var input = Data(repeating: 0xAA, count: 10)
        input.append(0x00)
        input.append(Data(repeating: 0xBB, count: 10))
        input.append(0x00)
        input.append(Data(repeating: 0xCC, count: 3))

        let result = demuxer.feed(input)
        #expect(result.audioBytes.count == 23)
    }

    @Test("Unicode in metadata")
    func unicodeMetadata() {
        var demuxer = ICYStreamDemuxer(metaint: 2)
        var input = Data(repeating: 0x11, count: 2)

        let metaString = "StreamTitle='Café ☕ Émission';"
        var metaBlock = Data(metaString.utf8)
        let pad = 16 - (metaBlock.count % 16)
        if pad < 16 { metaBlock.append(Data(repeating: 0x00, count: pad)) }

        input.append(UInt8(metaBlock.count / 16))
        input.append(metaBlock)

        let result = demuxer.feed(input)
        #expect(result.metadata?.streamTitle == "Café ☕ Émission")
    }

    @Test("malformed metadata does not crash")
    func malformedMetadata() {
        var demuxer = ICYStreamDemuxer(metaint: 2)
        var input = Data(repeating: 0x11, count: 2)

        let metaString = "NoEquals"
        var metaBlock = Data(metaString.utf8)
        let pad = 16 - (metaBlock.count % 16)
        if pad < 16 { metaBlock.append(Data(repeating: 0x00, count: pad)) }

        input.append(UInt8(metaBlock.count / 16))
        input.append(metaBlock)

        let result = demuxer.feed(input)
        #expect(result.audioBytes == Data(repeating: 0x11, count: 2))
    }

    @Test("metaint of zero returns all bytes as audio")
    func zeroMetaint() {
        var demuxer = ICYStreamDemuxer(metaint: 0)
        let input = Data(repeating: 0xAA, count: 50)
        let result = demuxer.feed(input)
        #expect(result.audioBytes == input)
        #expect(result.metadata == nil)
    }
}
