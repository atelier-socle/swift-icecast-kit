// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Connection Quality Scoring")
struct QualityScoreShowcaseTests {

    // MARK: - Showcase 1: Excellent score from perfect metrics

    @Test("Excellent score from perfect metrics")
    func excellentScoreFromPerfectMetrics() {
        let stats = ConnectionStatistics(
            bytesSent: 1_000_000,
            bytesTotal: 1_000_000,
            duration: 60.0,
            averageBitrate: 128_000,
            currentBitrate: 128_000,
            averageWriteLatency: 5.0,
            writeLatencyVariance: 0.5,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.grade == .excellent)
        #expect(quality.score > 0.9)
        #expect(quality.recommendation == nil)
    }

    // MARK: - Showcase 2: Critical score from degraded metrics

    @Test("Critical score from degraded metrics")
    func criticalScoreFromDegradedMetrics() {
        // writeLatency: 500ms → 0.0, stability: var 1000/avg 500 → 0.0,
        // throughput: 100/128000 → ~0.0, sendSuccess: 10/100 → 0.1,
        // reconnection: 10/5 → 0.0
        // score ≈ 0×0.30 + 0×0.25 + 0×0.20 + 0.1×0.15 + 0×0.10 = 0.015
        let stats = ConnectionStatistics(
            bytesSent: 100,
            bytesTotal: 100,
            duration: 60.0,
            averageBitrate: 100,
            currentBitrate: 100,
            reconnectionCount: 10,
            sendErrorCount: 90,
            averageWriteLatency: 500.0,
            writeLatencyVariance: 1000.0,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.grade == .critical)
        #expect(quality.score <= 0.3)
        #expect(quality.recommendation != nil)
    }

    // MARK: - Showcase 3: Write latency weight dominates (30%)

    @Test("Write latency weight (30%) dominates overall score")
    func writeLatencyWeightDominatesScore() {
        // Perfect everything except latency
        let stats = ConnectionStatistics(
            bytesSent: 1_000_000,
            bytesTotal: 1_000_000,
            duration: 60.0,
            averageBitrate: 128_000,
            currentBitrate: 128_000,
            averageWriteLatency: 500.0,
            writeLatencyVariance: 0.0,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.writeLatencyScore < 0.1)
        #expect(quality.score < 0.8)
    }

    // MARK: - Showcase 4: QualityGrade is comparable

    @Test("QualityGrade Comparable: excellent > good > fair > poor > critical")
    func qualityGradesAreComparableInOrder() {
        #expect(QualityGrade.excellent > .good)
        #expect(QualityGrade.good > .fair)
        #expect(QualityGrade.fair > .poor)
        #expect(QualityGrade.poor > .critical)
    }

    // MARK: - Showcase 5: RecommendationEngine produces relevant text

    @Test("RecommendationEngine produces relevant recommendation per grade")
    func recommendationEngineProducesRelevantRecommendation() {
        let engine = QualityRecommendationEngine()

        let excellent = ConnectionQuality(
            score: 0.95, grade: .excellent,
            writeLatencyScore: 1.0, stabilityScore: 1.0,
            throughputScore: 1.0, sendSuccessScore: 1.0,
            reconnectionScore: 1.0, recommendation: nil
        )
        #expect(engine.recommendation(for: excellent) == nil)

        let poor = ConnectionQuality(
            score: 0.25, grade: .poor,
            writeLatencyScore: 0.2, stabilityScore: 0.3,
            throughputScore: 0.2, sendSuccessScore: 0.3,
            reconnectionScore: 0.3, recommendation: nil
        )
        let rec = engine.recommendation(for: poor)
        #expect(rec != nil)
    }

    // MARK: - Showcase 6: from(statistics:targetBitrate:) throughput score

    @Test("Quality from statistics with explicit target bitrate affects throughput score")
    func qualityFromStatisticsWithTargetBitrate() {
        let stats = ConnectionStatistics(
            bytesSent: 500_000,
            bytesTotal: 500_000,
            duration: 30.0,
            averageBitrate: 64_000,
            currentBitrate: 64_000,
            averageWriteLatency: 5.0,
            writeLatencyVariance: 0.5,
            totalSendCount: 50
        )

        // Current bitrate = 64k, target = 128k → throughput ~50%
        let quality = ConnectionQuality.from(
            statistics: stats, targetBitrate: 128_000
        )
        #expect(quality.throughputScore < 0.6)

        // With target matching current → throughput 100%
        let matched = ConnectionQuality.from(
            statistics: stats, targetBitrate: 64_000
        )
        #expect(matched.throughputScore >= 0.99)
    }

    // MARK: - Showcase 7: QualityGrade init from score boundaries

    @Test("QualityGrade init from score covers all boundary values")
    func qualityGradeBoundaries() {
        #expect(QualityGrade(score: 1.0) == .excellent)
        #expect(QualityGrade(score: 0.91) == .excellent)
        #expect(QualityGrade(score: 0.80) == .good)
        #expect(QualityGrade(score: 0.71) == .good)
        #expect(QualityGrade(score: 0.60) == .fair)
        #expect(QualityGrade(score: 0.51) == .fair)
        #expect(QualityGrade(score: 0.40) == .poor)
        #expect(QualityGrade(score: 0.31) == .poor)
        #expect(QualityGrade(score: 0.30) == .critical)
        #expect(QualityGrade(score: 0.0) == .critical)
    }

    // MARK: - Showcase 8: QualityGrade labels

    @Test("QualityGrade labels are human-readable")
    func qualityGradeLabels() {
        #expect(QualityGrade.excellent.label == "Excellent")
        #expect(QualityGrade.good.label == "Good")
        #expect(QualityGrade.fair.label == "Fair")
        #expect(QualityGrade.poor.label == "Poor")
        #expect(QualityGrade.critical.label == "Critical")
    }

    // MARK: - Showcase 9: Zero-duration stats don't crash

    @Test("Quality computation handles zero-duration statistics gracefully")
    func zeroDurationHandledGracefully() {
        let stats = ConnectionStatistics()
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.score >= 0)
        #expect(quality.score <= 1.0)
        #expect(quality.throughputScore == 1.0)
        #expect(quality.sendSuccessScore == 1.0)
    }
}
