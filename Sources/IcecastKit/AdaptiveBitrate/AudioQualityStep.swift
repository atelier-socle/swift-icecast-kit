// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// A discrete audio quality level defined by bitrate and content type.
///
/// Quality steps represent the standard bitrate tiers for each audio format.
/// The adaptive bitrate system navigates between these steps based on
/// network conditions, always selecting the closest step at or below the
/// recommended bitrate.
public struct AudioQualityStep: Sendable, Hashable {

    /// The bitrate in bits per second.
    public let bitrate: Int

    /// A human-readable label (e.g., `"128k"`, `"96k"`).
    public let label: String

    /// The audio content type this step applies to.
    public let contentType: AudioContentType

    /// Creates a new audio quality step.
    ///
    /// - Parameters:
    ///   - bitrate: The bitrate in bits per second.
    ///   - label: A human-readable label.
    ///   - contentType: The audio content type.
    public init(bitrate: Int, label: String, contentType: AudioContentType) {
        self.bitrate = bitrate
        self.label = label
        self.contentType = contentType
    }

    // MARK: - Standard Steps

    /// Standard MP3 quality steps (320k down to 32k).
    public static let mp3Steps: [AudioQualityStep] = [
        AudioQualityStep(bitrate: 320_000, label: "320k", contentType: .mp3),
        AudioQualityStep(bitrate: 256_000, label: "256k", contentType: .mp3),
        AudioQualityStep(bitrate: 192_000, label: "192k", contentType: .mp3),
        AudioQualityStep(bitrate: 128_000, label: "128k", contentType: .mp3),
        AudioQualityStep(bitrate: 96_000, label: "96k", contentType: .mp3),
        AudioQualityStep(bitrate: 64_000, label: "64k", contentType: .mp3),
        AudioQualityStep(bitrate: 32_000, label: "32k", contentType: .mp3)
    ]

    /// Standard AAC quality steps (256k down to 32k).
    public static let aacSteps: [AudioQualityStep] = [
        AudioQualityStep(bitrate: 256_000, label: "256k", contentType: .aac),
        AudioQualityStep(bitrate: 192_000, label: "192k", contentType: .aac),
        AudioQualityStep(bitrate: 128_000, label: "128k", contentType: .aac),
        AudioQualityStep(bitrate: 96_000, label: "96k", contentType: .aac),
        AudioQualityStep(bitrate: 64_000, label: "64k", contentType: .aac),
        AudioQualityStep(bitrate: 48_000, label: "48k", contentType: .aac),
        AudioQualityStep(bitrate: 32_000, label: "32k", contentType: .aac)
    ]

    /// Standard Ogg/Opus quality steps (256k down to 16k).
    public static let opusSteps: [AudioQualityStep] = [
        AudioQualityStep(bitrate: 256_000, label: "256k", contentType: .oggOpus),
        AudioQualityStep(bitrate: 128_000, label: "128k", contentType: .oggOpus),
        AudioQualityStep(bitrate: 96_000, label: "96k", contentType: .oggOpus),
        AudioQualityStep(bitrate: 64_000, label: "64k", contentType: .oggOpus),
        AudioQualityStep(bitrate: 48_000, label: "48k", contentType: .oggOpus),
        AudioQualityStep(bitrate: 32_000, label: "32k", contentType: .oggOpus),
        AudioQualityStep(bitrate: 16_000, label: "16k", contentType: .oggOpus)
    ]

    /// Standard Ogg/Vorbis quality steps (320k down to 48k).
    public static let vorbisSteps: [AudioQualityStep] = [
        AudioQualityStep(bitrate: 320_000, label: "320k", contentType: .oggVorbis),
        AudioQualityStep(bitrate: 256_000, label: "256k", contentType: .oggVorbis),
        AudioQualityStep(bitrate: 192_000, label: "192k", contentType: .oggVorbis),
        AudioQualityStep(bitrate: 128_000, label: "128k", contentType: .oggVorbis),
        AudioQualityStep(bitrate: 96_000, label: "96k", contentType: .oggVorbis),
        AudioQualityStep(bitrate: 64_000, label: "64k", contentType: .oggVorbis),
        AudioQualityStep(bitrate: 48_000, label: "48k", contentType: .oggVorbis)
    ]

    // MARK: - Lookup

    /// Returns the standard quality steps for a given content type.
    ///
    /// - Parameter contentType: The audio content type.
    /// - Returns: An array of quality steps sorted by bitrate descending.
    public static func steps(for contentType: AudioContentType) -> [AudioQualityStep] {
        switch contentType {
        case .mp3:
            return mp3Steps
        case .aac:
            return aacSteps
        case .oggOpus:
            return opusSteps
        case .oggVorbis:
            return vorbisSteps
        default:
            return mp3Steps
        }
    }

    /// Returns the closest step at or below the given bitrate.
    ///
    /// If the given bitrate is below the minimum step for the content type,
    /// returns `nil`.
    ///
    /// - Parameters:
    ///   - bitrate: The target bitrate in bits per second.
    ///   - contentType: The audio content type.
    /// - Returns: The closest step at or below the bitrate, or `nil`.
    public static func closestStep(
        for bitrate: Int,
        contentType: AudioContentType
    ) -> AudioQualityStep? {
        let available = steps(for: contentType)
        return available.first { $0.bitrate <= bitrate }
    }
}
