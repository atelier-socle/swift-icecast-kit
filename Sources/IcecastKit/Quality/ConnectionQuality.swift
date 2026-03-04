// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Composite connection quality score aggregating multiple network health indicators.
///
/// The score is a weighted average of five individual metrics, each normalized
/// to [0.0, 1.0]:
///
/// | Metric | Weight |
/// |--------|--------|
/// | Write latency | 30% |
/// | Stability | 25% |
/// | Throughput | 20% |
/// | Send success rate | 15% |
/// | Reconnection frequency | 10% |
///
/// Create instances via the ``from(statistics:)`` or
/// ``from(statistics:targetBitrate:)`` factory methods.
public struct ConnectionQuality: Sendable {

    /// Composite score in [0.0, 1.0].
    public let score: Double

    /// Letter grade derived from score.
    public let grade: QualityGrade

    /// Write latency score (weight: 30%). 1.0 = latency under 20ms.
    public let writeLatencyScore: Double

    /// Connection stability score (weight: 25%). 1.0 = minimal variance.
    public let stabilityScore: Double

    /// Throughput score (weight: 20%). 1.0 = achieved equals target.
    public let throughputScore: Double

    /// Send success rate score (weight: 15%). 1.0 = zero failures.
    public let sendSuccessScore: Double

    /// Reconnection frequency score (weight: 10%). 1.0 = zero reconnections.
    public let reconnectionScore: Double

    /// Actionable recommendation, or nil if conditions are excellent.
    public let recommendation: String?

    // MARK: - Factory Methods

    /// Compute quality from existing connection statistics.
    ///
    /// Uses `averageBitrate` as the throughput target. When no streaming
    /// data is available yet, throughput score defaults to 1.0.
    ///
    /// - Parameter statistics: The current connection statistics snapshot.
    /// - Returns: A quality assessment with score, grade, and recommendation.
    public static func from(statistics: ConnectionStatistics) -> ConnectionQuality {
        let targetBps = statistics.averageBitrate
        return computeQuality(statistics: statistics, targetBps: targetBps)
    }

    /// Compute quality with an explicit target bitrate.
    ///
    /// Use this when the desired streaming bitrate is known and differs
    /// from the average bitrate reported by statistics.
    ///
    /// - Parameters:
    ///   - statistics: The current connection statistics snapshot.
    ///   - targetBitrate: The target bitrate in bits per second.
    /// - Returns: A quality assessment with score, grade, and recommendation.
    public static func from(
        statistics: ConnectionStatistics,
        targetBitrate: Int
    ) -> ConnectionQuality {
        computeQuality(statistics: statistics, targetBps: Double(targetBitrate))
    }

    // MARK: - Score Computation

    private static func computeQuality(
        statistics: ConnectionStatistics,
        targetBps: Double
    ) -> ConnectionQuality {
        let wl = computeWriteLatencyScore(statistics.averageWriteLatency)
        let st = computeStabilityScore(
            avgLatency: statistics.averageWriteLatency,
            variance: statistics.writeLatencyVariance
        )
        let tp = computeThroughputScore(
            currentBps: statistics.currentBitrate,
            targetBps: targetBps
        )
        let ss = computeSendSuccessScore(
            total: statistics.totalSendCount,
            failed: statistics.sendErrorCount
        )
        let rc = computeReconnectionScore(statistics.reconnectionCount)

        let score =
            wl * 0.30
            + st * 0.25
            + tp * 0.20
            + ss * 0.15
            + rc * 0.10
        let grade = QualityGrade(score: score)

        let partial = ConnectionQuality(
            score: score, grade: grade,
            writeLatencyScore: wl, stabilityScore: st,
            throughputScore: tp, sendSuccessScore: ss,
            reconnectionScore: rc, recommendation: nil
        )
        let engine = QualityRecommendationEngine()
        let recommendation = engine.recommendation(for: partial)

        return ConnectionQuality(
            score: score, grade: grade,
            writeLatencyScore: wl, stabilityScore: st,
            throughputScore: tp, sendSuccessScore: ss,
            reconnectionScore: rc, recommendation: recommendation
        )
    }

    /// `clamp(1.0 - (latencyMs - 20.0) / 480.0, 0.0, 1.0)`
    private static func computeWriteLatencyScore(_ latencyMs: Double) -> Double {
        clamp(1.0 - (latencyMs - 20.0) / 480.0)
    }

    /// `clamp(1.0 - variance / (avgLatency * 2.0), 0.0, 1.0)` — returns 1.0 if avgLatency is 0.
    private static func computeStabilityScore(
        avgLatency: Double,
        variance: Double
    ) -> Double {
        guard avgLatency > 0 else { return 1.0 }
        return clamp(1.0 - variance / (avgLatency * 2.0))
    }

    /// `clamp(achieved / target, 0.0, 1.0)` — returns 1.0 if target is 0.
    private static func computeThroughputScore(
        currentBps: Double,
        targetBps: Double
    ) -> Double {
        guard targetBps > 0 else { return 1.0 }
        return clamp(currentBps / targetBps)
    }

    /// `clamp((total - failed) / total, 0.0, 1.0)` — returns 1.0 if total is 0.
    private static func computeSendSuccessScore(
        total: Int,
        failed: Int
    ) -> Double {
        guard total > 0 else { return 1.0 }
        return clamp(Double(total - failed) / Double(total))
    }

    /// `clamp(1.0 - reconnections / 5.0, 0.0, 1.0)`
    private static func computeReconnectionScore(_ reconnections: Int) -> Double {
        clamp(1.0 - Double(reconnections) / 5.0)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}
