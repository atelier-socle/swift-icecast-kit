// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Adaptive Bitrate")
struct AdaptiveBitrateShowcaseTests {

    // MARK: - Showcase 1: Conservative policy recommends reduction under congestion

    @Test("Conservative policy recommends bitrate reduction under congestion")
    func conservativePolicyRecommendsBitrateReductionUnderCongestion() async {
        let policy = AdaptiveBitratePolicy.conservative
        let config = policy.configuration
        let monitor = NetworkConditionMonitor(
            policy: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: config.minBitrate,
                    maxBitrate: config.maxBitrate,
                    stepDown: config.stepDown,
                    stepUp: config.stepUp,
                    downTriggerThreshold: config.downTriggerThreshold,
                    upStabilityDuration: config.upStabilityDuration,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            ),
            currentBitrate: 128_000
        )
        await monitor.start()

        // Establish baseline with normal latency
        for _ in 0..<6 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 4000)
        }

        // Inject multiple congested writes to overcome EWMA smoothing
        let highLatency = 0.010 * config.downTriggerThreshold * 2.0
        for _ in 0..<5 {
            await monitor.recordWrite(duration: highLatency, bytesWritten: 4000)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 128_000)
    }

    // MARK: - Showcase 2: Aggressive policy recovers quickly

    @Test("Aggressive policy recovers quickly after stable period")
    func aggressivePolicyRecoversQuickly() async {
        // Start at a low bitrate to test recovery upward
        let monitor = NetworkConditionMonitor(
            policy: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: 32_000,
                    maxBitrate: 320_000,
                    stepDown: 0.75,
                    stepUp: 1.50,
                    downTriggerThreshold: 100.0,
                    upStabilityDuration: 0.0,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            ),
            currentBitrate: 64_000
        )
        await monitor.start()

        // Feed stable measurements — should trigger recovery
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 8000)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate > 64_000)
    }

    // MARK: - Showcase 3: AudioQualityStep tiers — MP3

    @Test("AudioQualityStep MP3 tiers cover expected bitrates")
    func audioQualityStepsMp3CoverExpectedBitrates() {
        let steps = AudioQualityStep.mp3Steps
        let bitrates = steps.map(\.bitrate)
        #expect(bitrates.contains(320_000))
        #expect(bitrates.contains(256_000))
        #expect(bitrates.contains(192_000))
        #expect(bitrates.contains(128_000))
        #expect(bitrates.contains(96_000))
        #expect(bitrates.contains(64_000))
        #expect(bitrates.contains(32_000))
        #expect(steps.count == 7)
    }

    // MARK: - Showcase 4: AudioQualityStep — all formats

    @Test("AudioQualityStep covers AAC, Opus, and Vorbis formats")
    func audioQualityStepsCoverAllFormats() {
        #expect(!AudioQualityStep.aacSteps.isEmpty)
        #expect(!AudioQualityStep.opusSteps.isEmpty)
        #expect(!AudioQualityStep.vorbisSteps.isEmpty)

        // Each format has its own steps
        #expect(AudioQualityStep.aacSteps.first?.contentType == .aac)
        #expect(AudioQualityStep.opusSteps.first?.contentType == .oggOpus)
        #expect(AudioQualityStep.vorbisSteps.first?.contentType == .oggVorbis)

        // Default for unknown content type is MP3 steps
        let custom = AudioContentType(rawValue: "audio/wav")
        let fallback = AudioQualityStep.steps(for: custom)
        #expect(fallback == AudioQualityStep.mp3Steps)
    }

    // MARK: - Showcase 5: NetworkConditionMonitor EWMA detects congestion

    @Test("NetworkConditionMonitor detects congestion via EWMA latency")
    func networkConditionMonitorDetectsCongestion() async {
        let monitor = NetworkConditionMonitor(
            policy: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: 32_000,
                    maxBitrate: 320_000,
                    downTriggerThreshold: 1.3,
                    upStabilityDuration: 60.0,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            ),
            currentBitrate: 256_000
        )
        await monitor.start()

        // Establish baseline
        for _ in 0..<6 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 8000)
        }

        let baselineLatency = await monitor.averageWriteLatency
        #expect(baselineLatency > 0)

        // Inject congested measurement
        await monitor.recordWrite(duration: 0.050, bytesWritten: 8000)

        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 256_000)
    }

    // MARK: - Showcase 6: NetworkConditionMonitor bandwidth estimation

    @Test("NetworkConditionMonitor estimates bandwidth from write measurements")
    func networkConditionMonitorEstimatesBandwidth() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive,
            currentBitrate: 128_000
        )
        await monitor.start()

        // Feed measurements: 4000 bytes in 0.01s = 3.2 Mbps
        for _ in 0..<5 {
            await monitor.recordWrite(duration: 0.01, bytesWritten: 4000)
        }

        let bandwidth = await monitor.estimatedBandwidth
        #expect(bandwidth > 0)
        #expect(await monitor.isMonitoring)
    }

    // MARK: - Showcase 7: BitrateRecommendation fields

    @Test("BitrateRecommendation carries direction, reason, and confidence")
    func bitrateRecommendationCarriesExpectedFields() {
        let rec = BitrateRecommendation(
            recommendedBitrate: 96_000,
            currentBitrate: 128_000,
            direction: .decrease,
            reason: .congestionDetected,
            confidence: 0.85
        )
        #expect(rec.recommendedBitrate == 96_000)
        #expect(rec.currentBitrate == 128_000)
        #expect(rec.direction == .decrease)
        #expect(rec.reason == .congestionDetected)
        #expect(rec.confidence == 0.85)
    }

    // MARK: - Showcase 8: Custom policy respects configuration

    @Test("Custom ABR policy respects min/max configuration")
    func customPolicyRespectsConfiguration() async {
        let customConfig = AdaptiveBitrateConfiguration(
            minBitrate: 64_000,
            maxBitrate: 192_000,
            stepDown: 0.80,
            stepUp: 1.10,
            downTriggerThreshold: 1.3,
            upStabilityDuration: 0.0,
            measurementWindow: 0.0,
            hysteresisCount: 1
        )
        let policy = AdaptiveBitratePolicy.custom(customConfig)
        #expect(policy.configuration.minBitrate == 64_000)
        #expect(policy.configuration.maxBitrate == 192_000)
        #expect(policy.configuration.stepDown == 0.80)
    }

    // MARK: - Showcase 9: RTT spike triggers congestion signal

    @Test("RTT spike triggers congestion signal (signal 2)")
    func rttSpikeDetectedAsCongestion() async {
        let monitor = NetworkConditionMonitor(
            policy: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: 32_000,
                    maxBitrate: 320_000,
                    downTriggerThreshold: 2.0,
                    upStabilityDuration: 60.0,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            ),
            currentBitrate: 256_000
        )
        await monitor.start()

        // Establish baseline with consistent 10ms latency
        for _ in 0..<6 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 8000)
        }

        // RTT spikes: well above 3× the EWMA, multiple to trigger hysteresis
        for _ in 0..<5 {
            await monitor.recordWrite(duration: 0.100, bytesWritten: 8000)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 256_000)
    }

    // MARK: - Showcase 10: Bandwidth slowdown triggers congestion signal

    @Test("Bandwidth below target triggers sendSlowdown signal (signal 3)")
    func bandwidthSlowdownDetected() async {
        let monitor = NetworkConditionMonitor(
            policy: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: 32_000,
                    maxBitrate: 320_000,
                    downTriggerThreshold: 5.0,
                    upStabilityDuration: 60.0,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            ),
            currentBitrate: 256_000
        )
        await monitor.start()

        // Establish baseline at high bandwidth
        for _ in 0..<6 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 32_000)
        }

        // Bandwidth suddenly drops below target (bitrateValue * 0.85)
        // Target: 256000 * 0.85 = 217600 bps
        // Write: 100 bytes in 0.01s = 80000 bps (well below target)
        await monitor.recordWrite(duration: 0.01, bytesWritten: 100)

        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 256_000)
    }

    // MARK: - Showcase 11: Write failure records congestion

    @Test("Write failure contributes to congestion signals")
    func writeFailureRecordsCongestion() async {
        let monitor = NetworkConditionMonitor(
            policy: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: 32_000,
                    maxBitrate: 320_000,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            ),
            currentBitrate: 128_000
        )
        await monitor.start()

        // Establish baseline
        for _ in 0..<6 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 8000)
        }

        await monitor.recordWriteFailure()
        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 128_000)
    }

    // MARK: - Showcase 12: Convenience constructor responsive(min:max:)

    @Test("Convenience constructor responsive(min:max:) overrides bounds")
    func responsiveConvenienceOverridesBounds() {
        let policy = AdaptiveBitratePolicy.responsive(min: 48_000, max: 256_000)
        #expect(policy.configuration.minBitrate == 48_000)
        #expect(policy.configuration.maxBitrate == 256_000)
        // Other responsive defaults preserved
        #expect(policy.configuration.hysteresisCount == 3)
    }

    // MARK: - Showcase 13: Convenience constructor conservative(min:max:)

    @Test("Convenience constructor conservative(min:max:) overrides bounds")
    func conservativeConvenienceOverridesBounds() {
        let policy = AdaptiveBitratePolicy.conservative(min: 64_000, max: 192_000)
        #expect(policy.configuration.minBitrate == 64_000)
        #expect(policy.configuration.maxBitrate == 192_000)
        // Other conservative defaults preserved
        #expect(policy.configuration.hysteresisCount == 5)
    }
}
