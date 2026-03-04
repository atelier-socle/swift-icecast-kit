// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - AudioQualityStep Tests

@Suite("AudioQualityStep")
struct AudioQualityStepTests {

    @Test("MP3 steps have correct count and values")
    func mp3StepsCountAndValues() {
        let steps = AudioQualityStep.mp3Steps
        #expect(steps.count == 7)
        #expect(steps[0].bitrate == 320_000)
        #expect(steps[1].bitrate == 256_000)
        #expect(steps[2].bitrate == 192_000)
        #expect(steps[3].bitrate == 128_000)
        #expect(steps[4].bitrate == 96_000)
        #expect(steps[5].bitrate == 64_000)
        #expect(steps[6].bitrate == 32_000)
    }

    @Test("AAC steps have correct count and values")
    func aacStepsCountAndValues() {
        let steps = AudioQualityStep.aacSteps
        #expect(steps.count == 7)
        #expect(steps[0].bitrate == 256_000)
        #expect(steps[1].bitrate == 192_000)
        #expect(steps[2].bitrate == 128_000)
        #expect(steps[3].bitrate == 96_000)
        #expect(steps[4].bitrate == 64_000)
        #expect(steps[5].bitrate == 48_000)
        #expect(steps[6].bitrate == 32_000)
    }

    @Test("Opus steps have correct count and values")
    func opusStepsCountAndValues() {
        let steps = AudioQualityStep.opusSteps
        #expect(steps.count == 7)
        #expect(steps[0].bitrate == 256_000)
        #expect(steps[1].bitrate == 128_000)
        #expect(steps[2].bitrate == 96_000)
        #expect(steps[3].bitrate == 64_000)
        #expect(steps[4].bitrate == 48_000)
        #expect(steps[5].bitrate == 32_000)
        #expect(steps[6].bitrate == 16_000)
    }

    @Test("Vorbis steps have correct count and values")
    func vorbisStepsCountAndValues() {
        let steps = AudioQualityStep.vorbisSteps
        #expect(steps.count == 7)
        #expect(steps[0].bitrate == 320_000)
        #expect(steps[6].bitrate == 48_000)
    }

    @Test("steps(for:) returns correct steps for each content type")
    func stepsForContentType() {
        #expect(AudioQualityStep.steps(for: .mp3).count == 7)
        #expect(AudioQualityStep.steps(for: .aac).count == 7)
        #expect(AudioQualityStep.steps(for: .oggOpus).count == 7)
        #expect(AudioQualityStep.steps(for: .oggVorbis).count == 7)
    }

    @Test("MP3 steps all have correct content type")
    func mp3StepsContentType() {
        for step in AudioQualityStep.mp3Steps {
            #expect(step.contentType == .mp3)
        }
    }

    @Test("AAC steps all have correct content type")
    func aacStepsContentType() {
        for step in AudioQualityStep.aacSteps {
            #expect(step.contentType == .aac)
        }
    }

    @Test("closestStep returns exact match")
    func closestStepExactMatch() {
        let step = AudioQualityStep.closestStep(for: 128_000, contentType: .mp3)
        #expect(step?.bitrate == 128_000)
        #expect(step?.label == "128k")
    }

    @Test("closestStep returns next lower for intermediate bitrate")
    func closestStepIntermediate() {
        let step = AudioQualityStep.closestStep(for: 200_000, contentType: .mp3)
        #expect(step?.bitrate == 192_000)
    }

    @Test("closestStep returns nil below minimum")
    func closestStepBelowMinimum() {
        let step = AudioQualityStep.closestStep(for: 16_000, contentType: .mp3)
        #expect(step == nil)
    }

    @Test("closestStep returns highest for very high bitrate")
    func closestStepAboveMaximum() {
        let step = AudioQualityStep.closestStep(for: 500_000, contentType: .mp3)
        #expect(step?.bitrate == 320_000)
    }

    @Test("closestStep for AAC intermediate value")
    func closestStepAACIntermediate() {
        let step = AudioQualityStep.closestStep(for: 100_000, contentType: .aac)
        #expect(step?.bitrate == 96_000)
    }

    @Test("closestStep for Opus returns nil below 16k")
    func closestStepOpusBelowMinimum() {
        let step = AudioQualityStep.closestStep(for: 10_000, contentType: .oggOpus)
        #expect(step == nil)
    }

    @Test("MP3 steps are sorted descending")
    func mp3StepsSortedDescending() {
        let steps = AudioQualityStep.mp3Steps
        for i in 0..<(steps.count - 1) {
            #expect(steps[i].bitrate > steps[i + 1].bitrate)
        }
    }

    @Test("Steps have non-empty labels")
    func stepsHaveLabels() {
        for step in AudioQualityStep.mp3Steps {
            #expect(!step.label.isEmpty)
        }
    }
}

// MARK: - BitrateRecommendation Tests

@Suite("BitrateRecommendation")
struct BitrateRecommendationTests {

    @Test("Construction with all fields")
    func constructionWithAllFields() {
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

    @Test("Confidence is clamped to 0.0–1.0")
    func confidenceClamped() {
        let high = BitrateRecommendation(
            recommendedBitrate: 128_000, currentBitrate: 96_000,
            direction: .increase, reason: .bandwidthRecovered, confidence: 1.5
        )
        #expect(high.confidence == 1.0)

        let low = BitrateRecommendation(
            recommendedBitrate: 64_000, currentBitrate: 128_000,
            direction: .decrease, reason: .congestionDetected, confidence: -0.5
        )
        #expect(low.confidence == 0.0)
    }

    @Test("Direction covers all cases")
    func directionCases() {
        let directions: [BitrateRecommendation.Direction] = [.increase, .decrease, .maintain]
        #expect(directions.count == 3)
    }

    @Test("Reason covers all cases")
    func reasonCases() {
        let reasons: [BitrateRecommendation.Reason] = [
            .congestionDetected, .bandwidthRecovered, .rttSpike, .sendSlowdown, .stable
        ]
        #expect(reasons.count == 5)
    }

    @Test("Direction raw values are correct")
    func directionRawValues() {
        #expect(BitrateRecommendation.Direction.increase.rawValue == "increase")
        #expect(BitrateRecommendation.Direction.decrease.rawValue == "decrease")
        #expect(BitrateRecommendation.Direction.maintain.rawValue == "maintain")
    }

    @Test("Reason raw values are correct")
    func reasonRawValues() {
        #expect(BitrateRecommendation.Reason.congestionDetected.rawValue == "congestionDetected")
        #expect(BitrateRecommendation.Reason.bandwidthRecovered.rawValue == "bandwidthRecovered")
        #expect(BitrateRecommendation.Reason.rttSpike.rawValue == "rttSpike")
        #expect(BitrateRecommendation.Reason.sendSlowdown.rawValue == "sendSlowdown")
        #expect(BitrateRecommendation.Reason.stable.rawValue == "stable")
    }

    @Test("BitrateRecommendation is Hashable")
    func isHashable() {
        let rec1 = BitrateRecommendation(
            recommendedBitrate: 96_000, currentBitrate: 128_000,
            direction: .decrease, reason: .congestionDetected, confidence: 0.8
        )
        let rec2 = BitrateRecommendation(
            recommendedBitrate: 96_000, currentBitrate: 128_000,
            direction: .decrease, reason: .congestionDetected, confidence: 0.8
        )
        #expect(rec1 == rec2)
    }
}

// MARK: - AdaptiveBitrateConfiguration Tests

@Suite("AdaptiveBitrateConfiguration")
struct AdaptiveBitrateConfigurationTests {

    @Test("Conservative preset has correct values")
    func conservativePreset() {
        let config = AdaptiveBitrateConfiguration.conservative
        #expect(config.stepDown == 0.85)
        #expect(config.stepUp == 1.05)
        #expect(config.upStabilityDuration == 60.0)
        #expect(config.hysteresisCount == 5)
        #expect(config.downTriggerThreshold == 1.5)
        #expect(config.measurementWindow == 10.0)
    }

    @Test("Responsive preset has correct values")
    func responsivePreset() {
        let config = AdaptiveBitrateConfiguration.responsive
        #expect(config.stepDown == 0.75)
        #expect(config.stepUp == 1.10)
        #expect(config.upStabilityDuration == 15.0)
        #expect(config.hysteresisCount == 3)
        #expect(config.downTriggerThreshold == 1.3)
        #expect(config.measurementWindow == 5.0)
    }

    @Test("Aggressive preset has correct values")
    func aggressivePreset() {
        let config = AdaptiveBitrateConfiguration.aggressive
        #expect(config.stepDown == 0.60)
        #expect(config.stepUp == 1.15)
        #expect(config.upStabilityDuration == 5.0)
        #expect(config.hysteresisCount == 1)
        #expect(config.downTriggerThreshold == 1.2)
        #expect(config.measurementWindow == 3.0)
    }

    @Test("All presets have stepDown less than 1.0")
    func presetsStepDownLessThanOne() {
        #expect(AdaptiveBitrateConfiguration.conservative.stepDown < 1.0)
        #expect(AdaptiveBitrateConfiguration.responsive.stepDown < 1.0)
        #expect(AdaptiveBitrateConfiguration.aggressive.stepDown < 1.0)
    }

    @Test("All presets have stepUp greater than 1.0")
    func presetsStepUpGreaterThanOne() {
        #expect(AdaptiveBitrateConfiguration.conservative.stepUp > 1.0)
        #expect(AdaptiveBitrateConfiguration.responsive.stepUp > 1.0)
        #expect(AdaptiveBitrateConfiguration.aggressive.stepUp > 1.0)
    }

    @Test("All presets have hysteresisCount greater than 0")
    func presetsHysteresisPositive() {
        #expect(AdaptiveBitrateConfiguration.conservative.hysteresisCount > 0)
        #expect(AdaptiveBitrateConfiguration.responsive.hysteresisCount > 0)
        #expect(AdaptiveBitrateConfiguration.aggressive.hysteresisCount > 0)
    }

    @Test("All presets have minBitrate less than maxBitrate")
    func presetsMinLessThanMax() {
        let c = AdaptiveBitrateConfiguration.conservative
        #expect(c.minBitrate < c.maxBitrate)
        let r = AdaptiveBitrateConfiguration.responsive
        #expect(r.minBitrate < r.maxBitrate)
        let a = AdaptiveBitrateConfiguration.aggressive
        #expect(a.minBitrate < a.maxBitrate)
    }

    @Test("Custom configuration preserves values")
    func customConfiguration() {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 48_000, maxBitrate: 256_000,
            stepDown: 0.80, stepUp: 1.08,
            downTriggerThreshold: 1.4, upStabilityDuration: 20.0,
            measurementWindow: 8.0, hysteresisCount: 4
        )
        #expect(config.minBitrate == 48_000)
        #expect(config.maxBitrate == 256_000)
        #expect(config.stepDown == 0.80)
        #expect(config.stepUp == 1.08)
        #expect(config.hysteresisCount == 4)
    }
}

// MARK: - AdaptiveBitratePolicy Tests

@Suite("AdaptiveBitratePolicy")
struct AdaptiveBitratePolicyTests {

    @Test("Responsive convenience returns correct config with custom bounds")
    func responsiveConvenience() {
        let policy = AdaptiveBitratePolicy.responsive(min: 64_000, max: 256_000)
        let config = policy.configuration
        #expect(config.minBitrate == 64_000)
        #expect(config.maxBitrate == 256_000)
        #expect(config.stepDown == AdaptiveBitrateConfiguration.responsive.stepDown)
        #expect(config.stepUp == AdaptiveBitrateConfiguration.responsive.stepUp)
    }

    @Test("Conservative convenience returns correct config with custom bounds")
    func conservativeConvenience() {
        let policy = AdaptiveBitratePolicy.conservative(min: 32_000, max: 192_000)
        let config = policy.configuration
        #expect(config.minBitrate == 32_000)
        #expect(config.maxBitrate == 192_000)
        #expect(config.stepDown == AdaptiveBitrateConfiguration.conservative.stepDown)
    }

    @Test("Custom policy passes configuration through")
    func customPolicy() {
        let customConfig = AdaptiveBitrateConfiguration(
            minBitrate: 16_000, maxBitrate: 320_000, stepDown: 0.50, stepUp: 1.20
        )
        let policy = AdaptiveBitratePolicy.custom(customConfig)
        let config = policy.configuration
        #expect(config.minBitrate == 16_000)
        #expect(config.stepDown == 0.50)
    }

    @Test("Named policies return correct configurations")
    func namedPolicies() {
        #expect(AdaptiveBitratePolicy.conservative.configuration.stepDown == 0.85)
        #expect(AdaptiveBitratePolicy.responsive.configuration.stepDown == 0.75)
        #expect(AdaptiveBitratePolicy.aggressive.configuration.stepDown == 0.60)
    }

    @Test("Policy configuration property returns matching preset")
    func policyConfigurationMatchesPreset() {
        let conservativeConfig = AdaptiveBitratePolicy.conservative.configuration
        #expect(conservativeConfig == AdaptiveBitrateConfiguration.conservative)

        let responsiveConfig = AdaptiveBitratePolicy.responsive.configuration
        #expect(responsiveConfig == AdaptiveBitrateConfiguration.responsive)

        let aggressiveConfig = AdaptiveBitratePolicy.aggressive.configuration
        #expect(aggressiveConfig == AdaptiveBitrateConfiguration.aggressive)
    }
}
