// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Result of a bandwidth probe measurement.
///
/// Contains measured upload bandwidth, write latency statistics,
/// a stability score, and a recommended audio bitrate based on the
/// probe results.
public struct IcecastProbeResult: Sendable {

    /// Achievable upload bandwidth in bits per second.
    public let uploadBandwidth: Double

    /// Average write latency in milliseconds.
    public let averageWriteLatency: Double

    /// Write latency variance in milliseconds.
    public let writeLatencyVariance: Double

    /// Connection stability score from 0 (unstable) to 100 (perfect).
    ///
    /// Computed as `100 * (1 - clamp(variance / averageLatency, 0, 1))`.
    public let stabilityScore: Double

    /// Recommended audio bitrate in bits per second based on probe results.
    ///
    /// Always corresponds to a valid ``AudioQualityStep`` for the probed
    /// content type.
    public let recommendedBitrate: Int

    /// Latency classification for buffer sizing decisions.
    public let latencyClass: LatencyClass

    /// Actual probe duration in seconds.
    public let duration: TimeInterval

    /// Icecast server version detected from response headers, if available.
    public let serverVersion: String?

    /// Latency classification thresholds for buffer sizing.
    public enum LatencyClass: String, Sendable, Codable {

        /// Less than 50ms — excellent for live streaming.
        case low

        /// 50–200ms — acceptable, standard buffers.
        case medium

        /// Greater than 200ms — requires larger buffers.
        case high

        /// Classifies a latency value in milliseconds.
        ///
        /// - Parameter latencyMs: The latency in milliseconds.
        /// - Returns: The appropriate latency class.
        public static func classify(_ latencyMs: Double) -> LatencyClass {
            if latencyMs < 50 {
                return .low
            } else if latencyMs <= 200 {
                return .medium
            } else {
                return .high
            }
        }
    }

    /// Creates a new probe result.
    ///
    /// - Parameters:
    ///   - uploadBandwidth: Achievable upload bandwidth in bps.
    ///   - averageWriteLatency: Average write latency in ms.
    ///   - writeLatencyVariance: Write latency variance in ms.
    ///   - stabilityScore: Stability score (0–100).
    ///   - recommendedBitrate: Recommended bitrate in bps.
    ///   - latencyClass: Latency classification.
    ///   - duration: Actual probe duration in seconds.
    ///   - serverVersion: Server version string, if detected.
    public init(
        uploadBandwidth: Double,
        averageWriteLatency: Double,
        writeLatencyVariance: Double,
        stabilityScore: Double,
        recommendedBitrate: Int,
        latencyClass: LatencyClass,
        duration: TimeInterval,
        serverVersion: String?
    ) {
        self.uploadBandwidth = uploadBandwidth
        self.averageWriteLatency = averageWriteLatency
        self.writeLatencyVariance = writeLatencyVariance
        self.stabilityScore = stabilityScore
        self.recommendedBitrate = recommendedBitrate
        self.latencyClass = latencyClass
        self.duration = duration
        self.serverVersion = serverVersion
    }
}
