// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("MetadataInterleaver")
struct MetadataInterleaverTests {

    // MARK: - Basic interleaving

    @Test("Audio chunk exactly metaint bytes → one metadata block appended")
    func exactMetaint() async throws {
        let interleaver = MetadataInterleaver(metaint: 8)
        let audio = Data([UInt8](repeating: 0xFF, count: 8))

        let output = try await interleaver.interleave(audio)

        // 8 audio bytes + 1 empty metadata byte (0x00)
        #expect(output.count == 9)
        #expect(output[8] == 0x00)
    }

    @Test("Audio chunk smaller than metaint → no metadata in output")
    func smallerThanMetaint() async throws {
        let interleaver = MetadataInterleaver(metaint: 16)
        let audio = Data([UInt8](repeating: 0xFF, count: 5))

        let output = try await interleaver.interleave(audio)

        #expect(output == audio)
    }

    @Test("Audio chunk larger than metaint → metadata at correct position")
    func largerThanMetaint() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        let audio = Data([UInt8](repeating: 0xFF, count: 6))

        let output = try await interleaver.interleave(audio)

        // 4 audio + 1 meta + 2 audio = 7
        #expect(output.count == 7)
        #expect(output[4] == 0x00)
        // Audio bytes at correct positions
        #expect(output[0] == 0xFF)
        #expect(output[5] == 0xFF)
        #expect(output[6] == 0xFF)
    }

    @Test("Audio = 2× metaint → two metadata blocks")
    func doubleMetaint() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        let audio = Data([UInt8](repeating: 0xFF, count: 8))

        let output = try await interleaver.interleave(audio)

        // 4 audio + 1 meta + 4 audio + 1 meta = 10
        #expect(output.count == 10)
        #expect(output[4] == 0x00)
        #expect(output[9] == 0x00)
    }

    @Test("Audio = 3× metaint → three metadata blocks")
    func tripleMetaint() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        let audio = Data([UInt8](repeating: 0xFF, count: 12))

        let output = try await interleaver.interleave(audio)

        // 4 + 1 + 4 + 1 + 4 + 1 = 15
        #expect(output.count == 15)
    }

    // MARK: - Metadata content

    @Test("With currentMetadata → encoded metadata inserted")
    func withMetadataContent() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        await interleaver.updateMetadata(ICYMetadata(streamTitle: "Hi"))
        let audio = Data([UInt8](repeating: 0xFF, count: 4))

        let output = try await interleaver.interleave(audio)

        // Metadata block starts at byte 4, first byte is N > 0
        #expect(output.count > 5)
        #expect(output[4] > 0)
    }

    @Test("With nil metadata → empty block (0x00) inserted")
    func withNilMetadata() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        let audio = Data([UInt8](repeating: 0xFF, count: 4))

        let output = try await interleaver.interleave(audio)

        #expect(output[4] == 0x00)
    }

    @Test("Update metadata between calls → new metadata at next interval")
    func updateBetweenCalls() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)

        // First call with no metadata
        let out1 = try await interleaver.interleave(
            Data([UInt8](repeating: 0xFF, count: 4)))
        #expect(out1[4] == 0x00)

        // Update metadata
        await interleaver.updateMetadata(ICYMetadata(streamTitle: "Song"))

        // Second call should have metadata
        let out2 = try await interleaver.interleave(
            Data([UInt8](repeating: 0xFF, count: 4)))
        #expect(out2[4] > 0)
    }

    @Test("Metadata persists across intervals")
    func metadataPersists() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        await interleaver.updateMetadata(ICYMetadata(streamTitle: "Song"))

        let audio = Data([UInt8](repeating: 0xFF, count: 8))
        let output = try await interleaver.interleave(audio)

        // Both metadata blocks should be non-empty
        #expect(output[4] > 0)
        let n1 = Int(output[4])
        let secondMetaOffset = 4 + 1 + n1 * 16 + 4
        #expect(output[secondMetaOffset] > 0)
    }

    // MARK: - Cross-call accumulation

    @Test("Two calls of metaint/2 each → metadata after second call")
    func crossCallAccumulation() async throws {
        let interleaver = MetadataInterleaver(metaint: 8)

        let out1 = try await interleaver.interleave(
            Data([UInt8](repeating: 0xFF, count: 4)))
        #expect(out1.count == 4)

        let out2 = try await interleaver.interleave(
            Data([UInt8](repeating: 0xFF, count: 4)))
        #expect(out2.count == 5)
        #expect(out2[4] == 0x00)
    }

    @Test("Many small chunks accumulate correctly")
    func manySmallChunks() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        var totalOutput = Data()

        for _ in 0..<4 {
            let out = try await interleaver.interleave(Data([0xFF]))
            totalOutput.append(out)
        }

        // After 4 bytes, we should have 4 audio bytes + 1 metadata byte
        #expect(totalOutput.count == 5)
        #expect(totalOutput[4] == 0x00)
    }

    // MARK: - Reset

    @Test("reset() clears counter → next call starts fresh")
    func resetClearsCounter() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)

        // Send 2 bytes (counter = 2)
        _ = try await interleaver.interleave(Data([0xFF, 0xFF]))

        // Reset
        await interleaver.reset()

        // Should need 4 more bytes for next metadata
        let out = try await interleaver.interleave(
            Data([UInt8](repeating: 0xFF, count: 4)))
        #expect(out.count == 5)
        #expect(out[4] == 0x00)
    }

    @Test("reset() clears metadata → empty blocks after reset")
    func resetClearsMetadata() async throws {
        let interleaver = MetadataInterleaver(metaint: 4)
        await interleaver.updateMetadata(ICYMetadata(streamTitle: "Song"))

        await interleaver.reset()

        let out = try await interleaver.interleave(
            Data([UInt8](repeating: 0xFF, count: 4)))
        #expect(out[4] == 0x00)

        let meta = await interleaver.currentMetadata
        #expect(meta == nil)
    }

    // MARK: - Edge cases

    @Test("Empty audio data → empty output")
    func emptyAudio() async throws {
        let interleaver = MetadataInterleaver(metaint: 8)
        let output = try await interleaver.interleave(Data())
        #expect(output.isEmpty)
    }

    @Test("metaint=1 → metadata after every byte")
    func metaintOne() async throws {
        let interleaver = MetadataInterleaver(metaint: 1)
        let audio = Data([0xFF, 0xFE, 0xFD])

        let output = try await interleaver.interleave(audio)

        // 1 byte + meta + 1 byte + meta + 1 byte + meta
        #expect(output.count == 6)
        #expect(output[0] == 0xFF)
        #expect(output[1] == 0x00)
        #expect(output[2] == 0xFE)
        #expect(output[3] == 0x00)
        #expect(output[4] == 0xFD)
        #expect(output[5] == 0x00)
    }
}
