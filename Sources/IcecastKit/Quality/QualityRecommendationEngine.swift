// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Generates actionable recommendation strings from quality metrics.
///
/// Uses a priority-based rule system where the first matching rule wins.
/// Returns `nil` when the connection quality is excellent (score above 0.9),
/// indicating no action is needed.
public struct QualityRecommendationEngine: Sendable {

    /// Creates a new recommendation engine.
    public init() {}

    /// Returns the highest-priority recommendation for the given quality,
    /// or `nil` if score is above 0.9 (excellent — no action needed).
    ///
    /// - Parameter quality: The connection quality to evaluate.
    /// - Returns: An actionable recommendation string, or `nil`.
    public func recommendation(for quality: ConnectionQuality) -> String? {
        if quality.score <= 0.3 && quality.writeLatencyScore < 0.3 {
            return
                "Critical: reduce audio bitrate immediately or check network connection"
        }
        if quality.score <= 0.3 {
            return "Critical: connection quality is severely degraded"
        }
        if quality.score <= 0.5 && quality.throughputScore < 0.8 {
            return "Consider switching to a lower quality preset"
        }
        if quality.score <= 0.5 && quality.reconnectionScore < 0.5 {
            return "Enable aggressive reconnect policy"
        }
        if quality.score <= 0.7 && quality.stabilityScore < 0.5 {
            return "Unstable connection detected, consider a wired network"
        }
        if quality.score <= 0.7 && quality.reconnectionScore < 0.7 {
            return "Frequent reconnections detected, check network stability"
        }
        if quality.score > 0.9 {
            return nil
        }
        return "Connection quality is degraded, monitor network conditions"
    }
}
