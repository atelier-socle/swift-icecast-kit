// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - QualityGrade Tests

@Suite("QualityGrade")
struct QualityGradeTests {

    @Test("init(score:) returns excellent for score > 0.9")
    func gradeExcellent() {
        #expect(QualityGrade(score: 0.91) == .excellent)
        #expect(QualityGrade(score: 1.0) == .excellent)
    }

    @Test("init(score:) returns good for score > 0.7")
    func gradeGood() {
        #expect(QualityGrade(score: 0.71) == .good)
        #expect(QualityGrade(score: 0.9) == .good)
    }

    @Test("init(score:) returns fair for score > 0.5")
    func gradeFair() {
        #expect(QualityGrade(score: 0.51) == .fair)
        #expect(QualityGrade(score: 0.7) == .fair)
    }

    @Test("init(score:) returns poor for score > 0.3")
    func gradePoor() {
        #expect(QualityGrade(score: 0.31) == .poor)
        #expect(QualityGrade(score: 0.5) == .poor)
    }

    @Test("init(score:) returns critical for score <= 0.3")
    func gradeCritical() {
        #expect(QualityGrade(score: 0.3) == .critical)
        #expect(QualityGrade(score: 0.0) == .critical)
        #expect(QualityGrade(score: -0.1) == .critical)
    }

    @Test("Comparable: excellent > good > fair > poor > critical")
    func gradeOrdering() {
        #expect(QualityGrade.excellent > .good)
        #expect(QualityGrade.good > .fair)
        #expect(QualityGrade.fair > .poor)
        #expect(QualityGrade.poor > .critical)
        #expect(QualityGrade.excellent > .critical)
    }

    @Test("label returns non-empty human-readable string for all cases")
    func gradeLabels() {
        for grade in QualityGrade.allCases {
            #expect(!grade.label.isEmpty)
        }
        #expect(QualityGrade.excellent.label == "Excellent")
        #expect(QualityGrade.critical.label == "Critical")
    }

    @Test("CaseIterable covers all 5 grades")
    func caseIterable() {
        #expect(QualityGrade.allCases.count == 5)
    }
}

// MARK: - ConnectionQuality Score Tests

@Suite("ConnectionQuality — Individual Scores")
struct ConnectionQualityScoreTests {

    @Test("writeLatencyScore: 20ms or below gives 1.0")
    func writeLatencyLow() {
        let stats = ConnectionStatistics(averageWriteLatency: 20.0)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.writeLatencyScore == 1.0)

        let stats0 = ConnectionStatistics(averageWriteLatency: 0.0)
        let quality0 = ConnectionQuality.from(statistics: stats0)
        #expect(quality0.writeLatencyScore > 1.0 - 0.001)
    }

    @Test("writeLatencyScore: 500ms gives 0.0")
    func writeLatencyHigh() {
        let stats = ConnectionStatistics(averageWriteLatency: 500.0)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.writeLatencyScore == 0.0)
    }

    @Test("writeLatencyScore: 260ms gives approximately 0.5")
    func writeLatencyMid() {
        let stats = ConnectionStatistics(averageWriteLatency: 260.0)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.writeLatencyScore >= 0.49)
        #expect(quality.writeLatencyScore <= 0.51)
    }

    @Test("stabilityScore: zero variance gives 1.0")
    func stabilityPerfect() {
        let stats = ConnectionStatistics(
            averageWriteLatency: 10.0,
            writeLatencyVariance: 0.0
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.stabilityScore == 1.0)
    }

    @Test("stabilityScore: avgLatency 0 gives 1.0")
    func stabilityNoLatency() {
        let stats = ConnectionStatistics(
            averageWriteLatency: 0.0,
            writeLatencyVariance: 5.0
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.stabilityScore == 1.0)
    }

    @Test("stabilityScore: high variance gives low score")
    func stabilityHighVariance() {
        let stats = ConnectionStatistics(
            averageWriteLatency: 10.0,
            writeLatencyVariance: 30.0
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.stabilityScore < 0.5)
    }

    @Test("throughputScore: achieved equals target gives 1.0")
    func throughputPerfect() {
        let stats = ConnectionStatistics(
            averageBitrate: 128_000,
            currentBitrate: 128_000
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.throughputScore == 1.0)
    }

    @Test("throughputScore: achieved is 0 gives 0.0")
    func throughputZero() {
        let stats = ConnectionStatistics(
            averageBitrate: 128_000,
            currentBitrate: 0
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.throughputScore == 0.0)
    }

    @Test("throughputScore: target is 0 gives 1.0")
    func throughputNoTarget() {
        let stats = ConnectionStatistics(
            averageBitrate: 0,
            currentBitrate: 128_000
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.throughputScore == 1.0)
    }

    @Test("sendSuccessScore: 0 failures gives 1.0")
    func sendSuccessAllGood() {
        let stats = ConnectionStatistics(
            sendErrorCount: 0,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.sendSuccessScore == 1.0)
    }

    @Test("sendSuccessScore: all failures gives 0.0")
    func sendSuccessAllFailed() {
        let stats = ConnectionStatistics(
            sendErrorCount: 50,
            totalSendCount: 50
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.sendSuccessScore == 0.0)
    }

    @Test("sendSuccessScore: total is 0 gives 1.0")
    func sendSuccessNoSends() {
        let stats = ConnectionStatistics(totalSendCount: 0)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.sendSuccessScore == 1.0)
    }

    @Test("reconnectionScore: 0 reconnections gives 1.0")
    func reconnectionNone() {
        let stats = ConnectionStatistics(reconnectionCount: 0)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.reconnectionScore == 1.0)
    }

    @Test("reconnectionScore: 5 reconnections gives 0.0")
    func reconnectionMax() {
        let stats = ConnectionStatistics(reconnectionCount: 5)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.reconnectionScore == 0.0)
    }

    @Test("reconnectionScore: 3 reconnections gives 0.4")
    func reconnectionMid() {
        let stats = ConnectionStatistics(reconnectionCount: 3)
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.reconnectionScore >= 0.39)
        #expect(quality.reconnectionScore <= 0.41)
    }
}

// MARK: - ConnectionQuality Composite Tests

@Suite("ConnectionQuality — Composite Score")
struct ConnectionQualityCompositeTests {

    @Test("Perfect metrics give score 1.0 and grade excellent")
    func perfectScore() {
        let stats = ConnectionStatistics(
            averageWriteLatency: 5.0,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.score > 0.9)
        #expect(quality.grade == .excellent)
    }

    @Test("All-zero metrics give high score (defaults favor no-data scenario)")
    func allZeroScore() {
        let stats = ConnectionStatistics()
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.score > 0.9)
    }

    @Test("Very poor metrics give low score and critical grade")
    func veryPoorScore() {
        let stats = ConnectionStatistics(
            averageBitrate: 128_000,
            currentBitrate: 0,
            reconnectionCount: 10,
            sendErrorCount: 90,
            averageWriteLatency: 600.0,
            writeLatencyVariance: 500.0,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.score <= 0.3)
        #expect(quality.grade == .critical)
    }

    @Test("writeLatencyScore impacts 30% of total score")
    func weightWriteLatency() {
        let goodStats = ConnectionStatistics(
            averageWriteLatency: 5.0,
            totalSendCount: 100
        )
        let badStats = ConnectionStatistics(
            averageWriteLatency: 600.0,
            totalSendCount: 100
        )
        let goodQ = ConnectionQuality.from(statistics: goodStats)
        let badQ = ConnectionQuality.from(statistics: badStats)
        let diff = goodQ.score - badQ.score
        #expect(diff >= 0.29)
        #expect(diff <= 0.31)
    }

    @Test("from(statistics:targetBitrate:) uses explicit target for throughput")
    func explicitTarget() {
        let stats = ConnectionStatistics(
            averageBitrate: 64_000,
            currentBitrate: 64_000
        )
        let qualityWithTarget = ConnectionQuality.from(
            statistics: stats, targetBitrate: 128_000
        )
        #expect(qualityWithTarget.throughputScore == 0.5)
    }

    @Test("from(statistics:) uses averageBitrate as target")
    func implicitTarget() {
        let stats = ConnectionStatistics(
            averageBitrate: 128_000,
            currentBitrate: 128_000
        )
        let quality = ConnectionQuality.from(statistics: stats)
        #expect(quality.throughputScore == 1.0)
    }

    @Test("recommendation is coherent with QualityRecommendationEngine")
    func recommendationCoherence() {
        let stats = ConnectionStatistics(
            averageBitrate: 128_000,
            currentBitrate: 10_000,
            reconnectionCount: 6,
            sendErrorCount: 80,
            averageWriteLatency: 600.0,
            writeLatencyVariance: 500.0,
            totalSendCount: 100
        )
        let quality = ConnectionQuality.from(statistics: stats)
        let engine = QualityRecommendationEngine()
        let expected = engine.recommendation(for: quality)
        #expect(quality.recommendation == expected)
    }
}

// MARK: - QualityRecommendationEngine Tests

@Suite("QualityRecommendationEngine")
struct QualityRecommendationEngineTests {

    private func makeQuality(
        score: Double,
        writeLatency: Double = 1.0,
        stability: Double = 1.0,
        throughput: Double = 1.0,
        sendSuccess: Double = 1.0,
        reconnection: Double = 1.0
    ) -> ConnectionQuality {
        ConnectionQuality(
            score: score,
            grade: QualityGrade(score: score),
            writeLatencyScore: writeLatency,
            stabilityScore: stability,
            throughputScore: throughput,
            sendSuccessScore: sendSuccess,
            reconnectionScore: reconnection,
            recommendation: nil
        )
    }

    @Test("score > 0.9 returns nil")
    func excellentNoRecommendation() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.95)
        #expect(engine.recommendation(for: quality) == nil)
    }

    @Test("score <= 0.3 with low writeLatencyScore returns critical bitrate message")
    func criticalLatency() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.2, writeLatency: 0.1)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("reduce audio bitrate") == true)
    }

    @Test("score <= 0.3 without low latency returns critical degraded message")
    func criticalGeneral() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.2, writeLatency: 0.5)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("severely degraded") == true)
    }

    @Test("score <= 0.5 with low throughput returns lower quality preset message")
    func poorThroughput() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.4, throughput: 0.5)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("lower quality preset") == true)
    }

    @Test("score <= 0.5 with low reconnection returns aggressive reconnect message")
    func poorReconnection() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.4, reconnection: 0.3)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("aggressive reconnect") == true)
    }

    @Test("score <= 0.7 with low stability returns wired network message")
    func fairUnstable() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.6, stability: 0.3)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("wired network") == true)
    }

    @Test("score <= 0.7 with low reconnection returns frequent reconnections message")
    func fairReconnections() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.6, reconnection: 0.5)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("Frequent reconnections") == true)
    }

    @Test("default case returns monitor message for scores between 0.7 and 0.9")
    func defaultRecommendation() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.8)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("monitor network") == true)
    }

    @Test("Priority: critical latency takes precedence over critical general")
    func priorityCriticalLatency() {
        let engine = QualityRecommendationEngine()
        let quality = makeQuality(score: 0.1, writeLatency: 0.1)
        let rec = engine.recommendation(for: quality)
        #expect(rec?.contains("reduce audio bitrate") == true)
    }
}
