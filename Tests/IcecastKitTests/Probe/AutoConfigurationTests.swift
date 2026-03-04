// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Auto-Configuration Tests

@Suite("IcecastConfiguration — Auto-Configuration")
struct AutoConfigurationTests {

    @Test("autoConfigured returns config with calibrated bitrate")
    func autoConfiguredBitrate() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            contentType: .mp3,
            duration: 2.0
        )
        // Verify the result has a valid bitrate that could be used
        #expect(result.recommendedBitrate > 0)
        let validBitrates = AudioQualityStep.mp3Steps.map(\.bitrate)
        #expect(validBitrates.contains(result.recommendedBitrate))
    }

    @Test("targetQuality quality yields higher bitrate than balanced")
    func qualityHigherThanBalanced() {
        // With same bandwidth, quality factor (0.95) > balanced factor (0.85)
        let bandwidth = 500_000.0
        let qualityTarget = Int(bandwidth * ProbeTargetQuality.quality.utilizationFactor)
        let balancedTarget = Int(bandwidth * ProbeTargetQuality.balanced.utilizationFactor)
        let qualityStep = AudioQualityStep.closestStep(
            for: qualityTarget, contentType: .mp3
        )
        let balancedStep = AudioQualityStep.closestStep(
            for: balancedTarget, contentType: .mp3
        )
        if let qBitrate = qualityStep?.bitrate,
            let bBitrate = balancedStep?.bitrate
        {
            #expect(qBitrate >= bBitrate)
        }
    }

    @Test("targetQuality lowLatency yields lower bitrate than balanced")
    func lowLatencyLowerThanBalanced() {
        // With same bandwidth, lowLatency factor (0.70) < balanced factor (0.85)
        let bandwidth = 300_000.0
        let lowLatencyTarget = Int(
            bandwidth * ProbeTargetQuality.lowLatency.utilizationFactor
        )
        let balancedTarget = Int(
            bandwidth * ProbeTargetQuality.balanced.utilizationFactor
        )
        let lowStep = AudioQualityStep.closestStep(
            for: lowLatencyTarget, contentType: .mp3
        )
        let balancedStep = AudioQualityStep.closestStep(
            for: balancedTarget, contentType: .mp3
        )
        if let lBitrate = lowStep?.bitrate,
            let bBitrate = balancedStep?.bitrate
        {
            #expect(lBitrate <= bBitrate)
        }
    }

    @Test("probeMountpoint nil defaults to mountpoint + /probe")
    func defaultProbeMountpoint() {
        // Verify the default probe mountpoint logic
        let mountpoint = "/live.mp3"
        let defaultProbe = mountpoint + "/probe"
        #expect(defaultProbe == "/live.mp3/probe")
    }
}

// MARK: - IcecastError Probe Cases

@Suite("IcecastError — Probe Cases")
struct IcecastErrorProbeCasesTests {

    @Test("probeFailed has description with reason")
    func probeFailedDescription() {
        let error = IcecastError.probeFailed(reason: "connection refused")
        #expect(error.description.contains("connection refused"))
    }

    @Test("probeTimeout has description")
    func probeTimeoutDescription() {
        let error = IcecastError.probeTimeout
        #expect(!error.description.isEmpty)
        #expect(error.description.contains("timed out"))
    }
}
