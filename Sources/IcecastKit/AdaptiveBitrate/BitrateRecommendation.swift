// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// A recommendation to adjust the audio encoding bitrate.
///
/// Emitted by ``NetworkConditionMonitor`` when network conditions change.
/// The consuming encoder should adjust its output bitrate accordingly.
/// IcecastKit recommends — the consumer decides.
public struct BitrateRecommendation: Sendable, Hashable {

    /// The recommended target bitrate in bits per second.
    public let recommendedBitrate: Int

    /// The current bitrate in bits per second at the time of recommendation.
    public let currentBitrate: Int

    /// The recommended direction of change.
    public let direction: Direction

    /// The reason for this recommendation.
    public let reason: Reason

    /// Confidence level of the recommendation (0.0–1.0).
    ///
    /// Higher values indicate stronger signal agreement.
    /// A confidence of 1.0 means all signals agree on the direction.
    public let confidence: Double

    /// Creates a new bitrate recommendation.
    ///
    /// - Parameters:
    ///   - recommendedBitrate: The target bitrate in bits per second.
    ///   - currentBitrate: The current bitrate in bits per second.
    ///   - direction: The recommended direction of change.
    ///   - reason: The reason for the recommendation.
    ///   - confidence: The confidence level (0.0–1.0).
    public init(
        recommendedBitrate: Int,
        currentBitrate: Int,
        direction: Direction,
        reason: Reason,
        confidence: Double
    ) {
        self.recommendedBitrate = recommendedBitrate
        self.currentBitrate = currentBitrate
        self.direction = direction
        self.reason = reason
        self.confidence = min(max(confidence, 0.0), 1.0)
    }

    /// The recommended direction of bitrate change.
    public enum Direction: String, Sendable, Hashable, Codable {

        /// Increase the bitrate — network conditions improved.
        case increase

        /// Decrease the bitrate — congestion or degradation detected.
        case decrease

        /// Maintain the current bitrate — conditions are stable.
        case maintain
    }

    /// The reason triggering the recommendation.
    public enum Reason: String, Sendable, Hashable, Codable {

        /// Send buffer saturation detected — TCP write backpressure.
        case congestionDetected

        /// Network conditions have improved after a degradation period.
        case bandwidthRecovered

        /// Sudden write latency spike detected.
        case rttSpike

        /// Write latency is gradually increasing.
        case sendSlowdown

        /// Conditions are stable — no change needed.
        case stable
    }
}
