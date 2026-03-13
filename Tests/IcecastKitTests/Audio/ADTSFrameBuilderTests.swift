// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ADTSFrameBuilder")
struct ADTSFrameBuilderTests {

    // MARK: - Header Generation

    @Test("ADTS sync word is 0xFFF")
    func syncWord() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0xAB, count: 100))
        #expect(frame[0] == 0xFF)
        #expect(frame[1] & 0xF0 == 0xF0)
    }

    @Test("ADTS header is 7 bytes without CRC")
    func headerSize() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let rawData = Data(repeating: 0x00, count: 50)
        let frame = try builder.wrap(rawData)
        #expect(frame.count == 57)  // 7 header + 50 payload
    }

    @Test("MPEG-4 ID bit is 0 and no CRC protection")
    func mpeg4NoCRC() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 48000, channelCount: 1)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        // Byte 1: 1111 0001 = 0xF1 (sync low + MPEG-4 + layer 00 + no CRC)
        #expect(frame[1] == 0xF1)
    }

    @Test("AAC-LC profile encoded correctly")
    func aacLCProfile() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2, profile: .lc)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        // Byte 2: profile=01 (LC) shifted left 6 = 0x40, sample rate index 4 (44100) shifted left 2 = 0x10
        // channel MSB for 2 channels: 0
        let profileBits = (frame[2] >> 6) & 0x03
        #expect(profileBits == AACProfile.lc.rawValue)
    }

    @Test("AAC Main profile encoded correctly")
    func aacMainProfile() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2, profile: .main)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let profileBits = (frame[2] >> 6) & 0x03
        #expect(profileBits == AACProfile.main.rawValue)
    }

    @Test("Sample rate 44100 Hz uses index 4")
    func sampleRate44100() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let srIndex = (frame[2] >> 2) & 0x0F
        #expect(srIndex == 4)
    }

    @Test("Sample rate 48000 Hz uses index 3")
    func sampleRate48000() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 48000, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let srIndex = (frame[2] >> 2) & 0x0F
        #expect(srIndex == 3)
    }

    @Test("Sample rate 96000 Hz uses index 0")
    func sampleRate96000() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 96000, channelCount: 1)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let srIndex = (frame[2] >> 2) & 0x0F
        #expect(srIndex == 0)
    }

    @Test("Mono channel config encoded correctly")
    func monoChannels() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 1)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        // Channel MSB in byte 2 bit 0, channel low in byte 3 bits 7-6
        let channelMSB = frame[2] & 0x01
        let channelLow = (frame[3] >> 6) & 0x03
        let channels = Int(channelMSB) << 2 | Int(channelLow)
        #expect(channels == 1)
    }

    @Test("Stereo channel config encoded correctly")
    func stereoChannels() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let channelMSB = frame[2] & 0x01
        let channelLow = (frame[3] >> 6) & 0x03
        let channels = Int(channelMSB) << 2 | Int(channelLow)
        #expect(channels == 2)
    }

    @Test("5.1 surround (6 channels) encoded correctly")
    func sixChannels() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 48000, channelCount: 6)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let channelMSB = frame[2] & 0x01
        let channelLow = (frame[3] >> 6) & 0x03
        let channels = Int(channelMSB) << 2 | Int(channelLow)
        #expect(channels == 6)
    }

    // MARK: - Frame Length

    @Test("Frame length encoded correctly for small payload")
    func frameLengthSmall() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let payload = Data(repeating: 0xAA, count: 100)
        let frame = try builder.wrap(payload)
        let expectedLength = 107  // 7 + 100

        let lengthHigh = Int(frame[3] & 0x03) << 11
        let lengthMid = Int(frame[4]) << 3
        let lengthLow = Int(frame[5] >> 5) & 0x07
        let decodedLength = lengthHigh | lengthMid | lengthLow
        #expect(decodedLength == expectedLength)
    }

    @Test("Frame length encoded correctly for typical AAC frame")
    func frameLengthTypical() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let payload = Data(repeating: 0xBB, count: 350)
        let frame = try builder.wrap(payload)
        let expectedLength = 357

        let lengthHigh = Int(frame[3] & 0x03) << 11
        let lengthMid = Int(frame[4]) << 3
        let lengthLow = Int(frame[5] >> 5) & 0x07
        let decodedLength = lengthHigh | lengthMid | lengthLow
        #expect(decodedLength == expectedLength)
    }

    @Test("Frame length at maximum (8191 bytes)")
    func frameLengthMax() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let payload = Data(repeating: 0xCC, count: 8184)  // 7 + 8184 = 8191
        let frame = try builder.wrap(payload)

        let lengthHigh = Int(frame[3] & 0x03) << 11
        let lengthMid = Int(frame[4]) << 3
        let lengthLow = Int(frame[5] >> 5) & 0x07
        let decodedLength = lengthHigh | lengthMid | lengthLow
        #expect(decodedLength == 8191)
    }

    // MARK: - Payload Integrity

    @Test("Payload data preserved after wrapping")
    func payloadIntegrity() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let payload = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let frame = try builder.wrap(payload)
        let extractedPayload = frame[7...]
        #expect(Array(extractedPayload) == [0x01, 0x02, 0x03, 0x04, 0x05])
    }

    @Test("Buffer fullness set to VBR (0x7FF)")
    func bufferFullnessVBR() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        // Buffer fullness: byte 5 low 5 bits + byte 6 high 6 bits = 0x7FF
        let bfHigh = Int(frame[5] & 0x1F) << 6
        let bfLow = Int(frame[6] >> 2) & 0x3F
        let bufferFullness = bfHigh | bfLow
        #expect(bufferFullness == 0x7FF)
    }

    @Test("Number of AAC frames minus 1 is 0")
    func singleFramePerADTS() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 10))
        let numFrames = frame[6] & 0x03
        #expect(numFrames == 0)  // 0 means 1 frame
    }

    // MARK: - Validation

    @Test("isADTS detects valid ADTS sync word")
    func isADTSValid() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let frame = try builder.wrap(Data(repeating: 0x00, count: 100))
        #expect(ADTSFrameBuilder.isADTS(frame))
    }

    @Test("isADTS rejects non-ADTS data")
    func isADTSInvalid() {
        let notADTS = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
        #expect(!ADTSFrameBuilder.isADTS(notADTS))
    }

    @Test("isADTS rejects data shorter than 7 bytes")
    func isADTSTooShort() {
        let short = Data([0xFF, 0xF1, 0x50])
        #expect(!ADTSFrameBuilder.isADTS(short))
    }

    // MARK: - Error Cases

    @Test("Empty raw AAC data throws invalidAudioData")
    func emptyDataThrows() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        #expect(throws: IcecastError.self) {
            try builder.wrap(Data())
        }
    }

    @Test("Oversized payload throws invalidAudioData")
    func oversizedPayloadThrows() throws {
        let builder = try ADTSFrameBuilder(
            configuration: AudioConfiguration(sampleRate: 44100, channelCount: 2)
        )
        let tooLarge = Data(repeating: 0x00, count: 8185)  // 7 + 8185 = 8192 > 8191
        #expect(throws: IcecastError.self) {
            try builder.wrap(tooLarge)
        }
    }

    @Test("Unsupported sample rate throws invalidAudioConfiguration")
    func unsupportedSampleRate() {
        #expect(throws: IcecastError.self) {
            try ADTSFrameBuilder(
                configuration: AudioConfiguration(sampleRate: 43000, channelCount: 2)
            )
        }
    }

    @Test("Zero channels throws invalidAudioConfiguration")
    func zeroChannels() {
        #expect(throws: IcecastError.self) {
            try ADTSFrameBuilder(
                configuration: AudioConfiguration(sampleRate: 44100, channelCount: 0)
            )
        }
    }

    @Test("Nine channels throws invalidAudioConfiguration")
    func nineChannels() {
        #expect(throws: IcecastError.self) {
            try ADTSFrameBuilder(
                configuration: AudioConfiguration(sampleRate: 44100, channelCount: 9)
            )
        }
    }
}
