// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Configuration parameters for the adaptive bitrate algorithm.
///
/// Controls how aggressively the system reacts to network changes,
/// how quickly it recovers, and the bitrate boundaries.
public struct AdaptiveBitrateConfiguration: Sendable, Hashable, Codable {

    /// Minimum bitrate floor in bits per second.
    ///
    /// The algorithm will never recommend a bitrate below this value.
    public var minBitrate: Int

    /// Maximum bitrate ceiling in bits per second.
    ///
    /// The algorithm will never recommend a bitrate above this value.
    public var maxBitrate: Int

    /// Step-down factor applied when reducing bitrate (e.g., 0.75 = −25%).
    ///
    /// Applied to the current bitrate to compute the next lower target.
    public var stepDown: Double

    /// Step-up factor applied when increasing bitrate (e.g., 1.10 = +10%).
    ///
    /// Applied to the current bitrate to compute the next higher target.
    public var stepUp: Double

    /// Threshold multiplier for write latency increase that triggers a decrease.
    ///
    /// When the EWMA write latency exceeds `baseline × downTriggerThreshold`,
    /// a congestion signal is raised. For example, 1.3 means a 30% increase.
    public var downTriggerThreshold: Double

    /// Duration in seconds of stable conditions required before increasing bitrate.
    ///
    /// The algorithm waits this long with low variance before recommending
    /// a bitrate increase to avoid premature recovery.
    public var upStabilityDuration: Double

    /// Measurement window in seconds for EWMA and variance calculations.
    public var measurementWindow: Double

    /// Number of consecutive signals in the same direction required
    /// before emitting a recommendation.
    ///
    /// Higher values reduce oscillation but increase reaction time.
    public var hysteresisCount: Int

    /// Creates a new adaptive bitrate configuration.
    ///
    /// - Parameters:
    ///   - minBitrate: Minimum bitrate floor in bits per second.
    ///   - maxBitrate: Maximum bitrate ceiling in bits per second.
    ///   - stepDown: Step-down factor (e.g., 0.75 = −25%).
    ///   - stepUp: Step-up factor (e.g., 1.10 = +10%).
    ///   - downTriggerThreshold: Latency increase multiplier threshold.
    ///   - upStabilityDuration: Seconds of stability required for increase.
    ///   - measurementWindow: Measurement window in seconds.
    ///   - hysteresisCount: Consecutive signals required before action.
    public init(
        minBitrate: Int,
        maxBitrate: Int,
        stepDown: Double = 0.75,
        stepUp: Double = 1.10,
        downTriggerThreshold: Double = 1.3,
        upStabilityDuration: Double = 15.0,
        measurementWindow: Double = 5.0,
        hysteresisCount: Int = 3
    ) {
        self.minBitrate = minBitrate
        self.maxBitrate = maxBitrate
        self.stepDown = stepDown
        self.stepUp = stepUp
        self.downTriggerThreshold = downTriggerThreshold
        self.upStabilityDuration = upStabilityDuration
        self.measurementWindow = measurementWindow
        self.hysteresisCount = hysteresisCount
    }

    // MARK: - Presets

    /// Conservative preset for 24/7 radio and live events.
    ///
    /// Slow step-down (−15%), very slow step-up (+5%), 60-second stability
    /// window, 5-signal hysteresis. Prioritizes stream continuity over quality.
    public static let conservative = AdaptiveBitrateConfiguration(
        minBitrate: 32_000,
        maxBitrate: 320_000,
        stepDown: 0.85,
        stepUp: 1.05,
        downTriggerThreshold: 1.5,
        upStabilityDuration: 60.0,
        measurementWindow: 10.0,
        hysteresisCount: 5
    )

    /// Responsive preset for live podcasts and interactive streams.
    ///
    /// Moderate step-down (−25%), moderate step-up (+10%), 15-second stability
    /// window, 3-signal hysteresis. Balances quality with responsiveness.
    public static let responsive = AdaptiveBitrateConfiguration(
        minBitrate: 32_000,
        maxBitrate: 320_000,
        stepDown: 0.75,
        stepUp: 1.10,
        downTriggerThreshold: 1.3,
        upStabilityDuration: 15.0,
        measurementWindow: 5.0,
        hysteresisCount: 3
    )

    /// Aggressive preset for testing and development.
    ///
    /// Fast step-down (−40%), fast step-up (+15%), 5-second stability
    /// window, 1-signal hysteresis. Reacts immediately to changes.
    public static let aggressive = AdaptiveBitrateConfiguration(
        minBitrate: 32_000,
        maxBitrate: 320_000,
        stepDown: 0.60,
        stepUp: 1.15,
        downTriggerThreshold: 1.2,
        upStabilityDuration: 5.0,
        measurementWindow: 3.0,
        hysteresisCount: 1
    )
}
