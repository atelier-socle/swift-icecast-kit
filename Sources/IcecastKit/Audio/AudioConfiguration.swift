// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Configuration for raw AAC audio that needs ADTS wrapping.
///
/// Used with ``IcecastClient/send(rawAAC:)`` to automatically wrap
/// raw AAC access units in ADTS frames (ISO 13818-7) before sending.
///
/// ```swift
/// let audioConfig = AudioConfiguration(sampleRate: 44100, channelCount: 2)
/// try await client.send(rawAAC: aacFrame, audioConfiguration: audioConfig)
/// ```
public struct AudioConfiguration: Sendable, Hashable {

    /// Sample rate in Hz.
    public let sampleRate: Int

    /// Number of audio channels (1 = mono, 2 = stereo, up to 8).
    public let channelCount: Int

    /// AAC profile. Defaults to `.lc` (Low Complexity).
    public let profile: AACProfile

    /// Creates an audio configuration for ADTS wrapping.
    ///
    /// - Parameters:
    ///   - sampleRate: Sample rate in Hz (e.g. 44100, 48000).
    ///   - channelCount: Number of channels (1-8).
    ///   - profile: AAC profile. Defaults to `.lc`.
    public init(sampleRate: Int, channelCount: Int, profile: AACProfile = .lc) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.profile = profile
    }

    /// The ADTS sample rate index for this configuration's sample rate.
    ///
    /// Returns `nil` if the sample rate is not in the ADTS table.
    var sampleRateIndex: UInt8? {
        Self.sampleRateTable[sampleRate]
    }

    /// ADTS sample rate index lookup table (ISO 13818-7, Table 36).
    static let sampleRateTable: [Int: UInt8] = [
        96000: 0, 88200: 1, 64000: 2, 48000: 3,
        44100: 4, 32000: 5, 24000: 6, 22050: 7,
        16000: 8, 12000: 9, 11025: 10, 8000: 11,
        7350: 12
    ]
}
