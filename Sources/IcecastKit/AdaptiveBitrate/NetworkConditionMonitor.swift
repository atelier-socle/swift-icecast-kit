// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Monitors network conditions and emits adaptive bitrate recommendations.
///
/// The monitor runs during active streaming, receiving write measurements
/// from ``IcecastClient`` after each `send()` call. It tracks TCP write
/// latency and bandwidth using EWMA (Exponentially Weighted Moving Average)
/// and emits ``BitrateRecommendation`` events when conditions change.
///
/// **Principle**: IcecastKit recommends — the consumer (encoder) adjusts.
///
/// The algorithm uses four congestion signals:
/// - Write latency exceeding baseline threshold → ``BitrateRecommendation/Reason/congestionDetected``
/// - Sudden write duration spike (3× normal) → ``BitrateRecommendation/Reason/rttSpike``
/// - Bandwidth below target → ``BitrateRecommendation/Reason/sendSlowdown``
/// - Write failure → contributes to congestion signal count
///
/// And one recovery signal:
/// - Stable latency (variance < 20%) for the configured duration
///   → ``BitrateRecommendation/Reason/bandwidthRecovered``
public actor NetworkConditionMonitor {

    // MARK: - Properties

    private let configuration: AdaptiveBitrateConfiguration
    private let recommendationContinuation: AsyncStream<BitrateRecommendation>.Continuation
    private var bitrateValue: Int
    private var monitoring: Bool = false

    // EWMA state
    private var ewmaLatency: Double = 0.0
    private var ewmaBandwidth: Double = 0.0
    private var ewmaVariance: Double = 0.0
    private var baselineLatency: Double = 0.0
    private var baselineEstablished: Bool = false
    private var measurementCount: Int = 0
    private var firstMeasurementTime: Date?

    // Hysteresis tracking
    private var consecutiveDecreaseSignals: Int = 0
    private var consecutiveIncreaseSignals: Int = 0
    private var lastDirection: BitrateRecommendation.Direction = .maintain
    private var lastCongestionReason: BitrateRecommendation.Reason = .stable

    // Recovery tracking
    private var stableStartTime: Date?

    // EWMA smoothing factors
    private let latencyAlpha: Double = 0.2
    private let bandwidthAlpha: Double = 0.1
    private let varianceAlpha: Double = 0.2

    /// Stream of bitrate recommendations.
    ///
    /// Consumers iterate over this stream to receive real-time
    /// recommendations for adjusting the encoding bitrate.
    public nonisolated let recommendations: AsyncStream<BitrateRecommendation>

    // MARK: - Initialization

    /// Creates a new network condition monitor.
    ///
    /// - Parameters:
    ///   - policy: The adaptive bitrate policy to use.
    ///   - currentBitrate: The initial bitrate in bits per second.
    public init(policy: AdaptiveBitratePolicy, currentBitrate: Int) {
        self.configuration = policy.configuration
        self.bitrateValue = currentBitrate
        let (stream, continuation) = AsyncStream<BitrateRecommendation>.makeStream()
        self.recommendations = stream
        self.recommendationContinuation = continuation
    }

    deinit {
        recommendationContinuation.finish()
    }

    // MARK: - Lifecycle

    /// Starts network condition monitoring.
    ///
    /// Called by ``IcecastClient`` after a successful connection.
    /// Resets all internal state for a fresh monitoring session.
    /// Calling `start()` on an already-started monitor is a no-op.
    public func start() {
        guard !monitoring else { return }
        monitoring = true
        resetState()
    }

    /// Stops network condition monitoring.
    ///
    /// Called by ``IcecastClient`` on disconnection.
    /// Calling `stop()` on a stopped monitor is a no-op.
    public func stop() {
        guard monitoring else { return }
        monitoring = false
    }

    // MARK: - Measurement Recording

    /// Records a write measurement from a `send()` call.
    ///
    /// The monitor uses the duration and bytes to compute write latency
    /// and bandwidth estimates, then evaluates congestion/recovery signals.
    ///
    /// - Parameters:
    ///   - duration: Time in seconds that the `send()` call took.
    ///   - bytesWritten: Number of bytes sent.
    public func recordWrite(duration: Double, bytesWritten: Int) {
        guard monitoring, duration > 0, bytesWritten > 0 else { return }

        let now = Date()
        let latencyMs = duration * 1000.0
        let instantBandwidth = Double(bytesWritten) * 8.0 / duration

        updateEWMA(latencyMs: latencyMs, bandwidth: instantBandwidth, now: now)
        evaluateSignals(instantLatencyMs: latencyMs, now: now)
    }

    /// Records a write failure.
    ///
    /// Write failures contribute to the congestion signal count,
    /// increasing the likelihood of a decrease recommendation.
    public func recordWriteFailure() {
        guard monitoring else { return }
        consecutiveDecreaseSignals += 1
        consecutiveIncreaseSignals = 0
        stableStartTime = nil
        lastCongestionReason = .congestionDetected
        checkHysteresisAndEmit(direction: .decrease, reason: .congestionDetected)
    }

    // MARK: - Observable State

    /// The current target bitrate in bits per second.
    ///
    /// Updated when a recommendation is emitted.
    public var currentBitrate: Int { bitrateValue }

    /// The average write latency in milliseconds (EWMA-smoothed).
    public var averageWriteLatency: Double { ewmaLatency }

    /// The estimated bandwidth in bits per second (EWMA-smoothed).
    public var estimatedBandwidth: Double { ewmaBandwidth }

    /// Whether the monitor is actively processing measurements.
    public var isMonitoring: Bool { monitoring }

    // MARK: - Private — EWMA

    /// Updates EWMA values with a new measurement.
    private func updateEWMA(latencyMs: Double, bandwidth: Double, now: Date) {
        measurementCount += 1

        if measurementCount == 1 {
            ewmaLatency = latencyMs
            ewmaBandwidth = bandwidth
            ewmaVariance = 0.0
            firstMeasurementTime = now
        } else {
            let latencyDiff = latencyMs - ewmaLatency
            ewmaLatency = latencyAlpha * latencyMs + (1.0 - latencyAlpha) * ewmaLatency
            ewmaBandwidth = bandwidthAlpha * bandwidth + (1.0 - bandwidthAlpha) * ewmaBandwidth
            ewmaVariance =
                varianceAlpha * (latencyDiff * latencyDiff)
                + (1.0 - varianceAlpha) * ewmaVariance
        }

        // Establish baseline after the measurement window
        if !baselineEstablished, let firstTime = firstMeasurementTime {
            let elapsed = now.timeIntervalSince(firstTime)
            if elapsed >= configuration.measurementWindow && measurementCount >= 5 {
                baselineLatency = ewmaLatency
                baselineEstablished = true
            }
        }
    }

    // MARK: - Private — Signal Evaluation

    /// Evaluates congestion and recovery signals from current state.
    private func evaluateSignals(instantLatencyMs: Double, now: Date) {
        guard baselineEstablished, baselineLatency > 0 else { return }

        // Congestion signal 1: EWMA latency exceeds baseline × threshold
        if ewmaLatency > baselineLatency * configuration.downTriggerThreshold {
            recordCongestionSignal(reason: .congestionDetected)
            return
        }

        // Congestion signal 2: sudden spike (3× the EWMA)
        if instantLatencyMs > ewmaLatency * 3.0 {
            recordCongestionSignal(reason: .rttSpike)
            return
        }

        // Congestion signal 3: bandwidth below target
        if ewmaBandwidth < Double(bitrateValue) * 0.85 {
            recordCongestionSignal(reason: .sendSlowdown)
            return
        }

        // No congestion — check recovery
        consecutiveDecreaseSignals = 0

        let coefficientOfVariation =
            ewmaLatency > 0
            ? (ewmaVariance.squareRoot() / ewmaLatency) : 0.0

        if coefficientOfVariation < 0.20 {
            // Conditions are stable
            if stableStartTime == nil {
                stableStartTime = now
            }
            if let stableStart = stableStartTime {
                let stableDuration = now.timeIntervalSince(stableStart)
                if stableDuration >= configuration.upStabilityDuration
                    && bitrateValue < configuration.maxBitrate
                {
                    recordRecoverySignal()
                }
            }
        } else {
            stableStartTime = nil
            consecutiveIncreaseSignals = 0
        }
    }

    /// Records a congestion signal and checks hysteresis.
    private func recordCongestionSignal(reason: BitrateRecommendation.Reason) {
        consecutiveDecreaseSignals += 1
        consecutiveIncreaseSignals = 0
        stableStartTime = nil
        lastCongestionReason = reason
        checkHysteresisAndEmit(direction: .decrease, reason: reason)
    }

    /// Records a recovery signal and checks hysteresis.
    private func recordRecoverySignal() {
        consecutiveIncreaseSignals += 1
        checkHysteresisAndEmit(direction: .increase, reason: .bandwidthRecovered)
    }

    // MARK: - Private — Hysteresis & Emission

    /// Checks if the hysteresis threshold is met and emits a recommendation.
    private func checkHysteresisAndEmit(
        direction: BitrateRecommendation.Direction,
        reason: BitrateRecommendation.Reason
    ) {
        let signalCount: Int
        switch direction {
        case .decrease:
            signalCount = consecutiveDecreaseSignals
        case .increase:
            signalCount = consecutiveIncreaseSignals
        case .maintain:
            return
        }

        guard signalCount >= configuration.hysteresisCount else { return }

        let newBitrate = computeNewBitrate(direction: direction)
        guard newBitrate != bitrateValue else { return }

        let confidence = computeConfidence(signalCount: signalCount)

        let recommendation = BitrateRecommendation(
            recommendedBitrate: newBitrate,
            currentBitrate: bitrateValue,
            direction: direction,
            reason: reason,
            confidence: confidence
        )

        bitrateValue = newBitrate
        lastDirection = direction
        resetHysteresis()
        stableStartTime = nil

        // Update baseline after decrease to track new normal
        if direction == .decrease {
            baselineLatency = ewmaLatency
        }

        recommendationContinuation.yield(recommendation)
    }

    /// Computes the new bitrate based on direction and step factors.
    private func computeNewBitrate(direction: BitrateRecommendation.Direction) -> Int {
        let raw: Int
        switch direction {
        case .decrease:
            raw = Int(Double(bitrateValue) * configuration.stepDown)
        case .increase:
            raw = Int(Double(bitrateValue) * configuration.stepUp)
        case .maintain:
            return bitrateValue
        }

        let clamped = max(configuration.minBitrate, min(configuration.maxBitrate, raw))

        // Snap to the closest quality step if available
        if let step = AudioQualityStep.closestStep(for: clamped, contentType: .mp3) {
            return max(configuration.minBitrate, min(configuration.maxBitrate, step.bitrate))
        }
        return clamped
    }

    /// Computes confidence from signal count relative to hysteresis.
    private func computeConfidence(signalCount: Int) -> Double {
        let ratio = Double(signalCount) / Double(max(configuration.hysteresisCount, 1))
        return min(ratio, 1.0)
    }

    /// Resets hysteresis counters after emitting a recommendation.
    private func resetHysteresis() {
        consecutiveDecreaseSignals = 0
        consecutiveIncreaseSignals = 0
    }

    /// Resets all internal state for a fresh monitoring session.
    private func resetState() {
        ewmaLatency = 0.0
        ewmaBandwidth = 0.0
        ewmaVariance = 0.0
        baselineLatency = 0.0
        baselineEstablished = false
        measurementCount = 0
        firstMeasurementTime = nil
        consecutiveDecreaseSignals = 0
        consecutiveIncreaseSignals = 0
        lastDirection = .maintain
        lastCongestionReason = .stable
        stableStartTime = nil
    }
}
