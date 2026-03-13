// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Builds ADTS (Audio Data Transport Stream) frames from raw AAC data.
///
/// Wraps raw AAC access units with a 7-byte ADTS header per ISO 13818-7.
/// The header contains sync word, profile, sample rate, channel config,
/// and frame length, enabling Icecast to deliver the stream to listeners.
///
/// ADTS header layout (7 bytes, no CRC):
/// ```
/// Byte 0:    [sync word high: 0xFF]
/// Byte 1:    [sync word low: 1111] [ID: 0=MPEG-4] [layer: 00] [no CRC: 1]
/// Byte 2:    [profile: 2 bits] [sample rate index: 4 bits] [private: 0] [channel MSB: 1 bit]
/// Byte 3:    [channel low: 2 bits] [originality: 0] [home: 0] [copyright: 0] [start: 0] [frame length high: 2 bits]
/// Byte 4:    [frame length mid: 8 bits]
/// Byte 5:    [frame length low: 3 bits] [buffer fullness high: 5 bits]
/// Byte 6:    [buffer fullness low: 6 bits] [frames minus 1: 2 bits]
/// ```
struct ADTSFrameBuilder: Sendable {

    /// The audio configuration used for header generation.
    let configuration: AudioConfiguration

    /// Cached ADTS header bytes 0-2 (constant across frames).
    private let byte0: UInt8
    private let byte1: UInt8
    private let byte2: UInt8

    /// Cached ADTS header byte 3 base (channel low bits, frame length filled per frame).
    private let byte3Base: UInt8

    /// Creates a frame builder for the given audio configuration.
    ///
    /// - Parameter configuration: The audio configuration.
    /// - Throws: ``IcecastError/invalidAudioConfiguration(reason:)`` if the
    ///   sample rate or channel count is not supported by ADTS.
    init(configuration: AudioConfiguration) throws {
        guard let sampleRateIndex = configuration.sampleRateIndex else {
            throw IcecastError.invalidAudioConfiguration(
                reason: "Unsupported sample rate \(configuration.sampleRate) Hz for ADTS"
            )
        }

        guard (1...8).contains(configuration.channelCount) else {
            throw IcecastError.invalidAudioConfiguration(
                reason: "Channel count must be 1-8, got \(configuration.channelCount)"
            )
        }

        self.configuration = configuration

        let profile = configuration.profile.rawValue
        let channels = UInt8(configuration.channelCount)

        // Byte 0: sync word high
        let byte0: UInt8 = 0xFF
        // Byte 1: sync word low (4) + MPEG-4 ID (1=0) + layer (2=00) + no CRC (1=1)
        let byte1: UInt8 = 0xF1
        // Byte 2: profile (2) + sample rate index (4) + private (1=0) + channel MSB (1)
        let byte2: UInt8 = (profile << 6) | (sampleRateIndex << 2) | ((channels >> 2) & 0x01)
        // Byte 3 partial: channel low (2) + 4 zero bits + frame length high (2) — length filled per frame
        let byte3Base: UInt8 = (channels & 0x03) << 6

        self.byte0 = byte0
        self.byte1 = byte1
        self.byte2 = byte2
        self.byte3Base = byte3Base
    }

    /// Wraps raw AAC data in an ADTS frame.
    ///
    /// - Parameter rawAAC: Raw AAC access unit data (without ADTS header).
    /// - Returns: Complete ADTS frame (7-byte header + raw AAC data).
    /// - Throws: ``IcecastError/invalidAudioData(reason:)`` if the data is empty
    ///   or the resulting frame exceeds the ADTS maximum of 8191 bytes.
    func wrap(_ rawAAC: Data) throws -> Data {
        guard !rawAAC.isEmpty else {
            throw IcecastError.invalidAudioData(reason: "Raw AAC data is empty")
        }

        let frameLength = 7 + rawAAC.count
        guard frameLength <= 8191 else {
            throw IcecastError.invalidAudioData(
                reason: "ADTS frame too large: \(frameLength) bytes (max 8191)"
            )
        }

        var frame = Data(capacity: frameLength)

        // Bytes 0-2: from cached values
        frame.append(byte0)
        frame.append(byte1)
        frame.append(byte2)

        // Byte 3: channel low bits + frame length high 2 bits
        let byte3 = byte3Base | UInt8((frameLength >> 11) & 0x03)
        frame.append(byte3)

        // Byte 4: frame length mid 8 bits
        frame.append(UInt8((frameLength >> 3) & 0xFF))

        // Byte 5: frame length low 3 bits + buffer fullness high 5 bits (0x7FF = VBR)
        frame.append(UInt8((frameLength & 0x07) << 5) | 0x1F)

        // Byte 6: buffer fullness low 6 bits + number of frames minus 1 (0 = 1 frame)
        frame.append(0xFC)

        // Payload
        frame.append(rawAAC)

        return frame
    }

    /// Validates that data starts with a valid ADTS sync word.
    ///
    /// - Parameter data: Data to validate.
    /// - Returns: `true` if the data begins with 0xFFF (ADTS sync word).
    static func isADTS(_ data: Data) -> Bool {
        guard data.count >= 7 else { return false }
        return data[data.startIndex] == 0xFF
            && (data[data.startIndex + 1] & 0xF0) == 0xF0
    }
}
