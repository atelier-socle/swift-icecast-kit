// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Bandwidth Probe")
struct BandwidthProbeShowcaseTests {

    private static let putOKResponse = Data(
        "HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8
    )

    // MARK: - Showcase 1: Well-formed probe result

    @Test("Probe returns well-formed result with all fields populated")
    func probeReturnsWellFormedResult() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            contentType: .mp3,
            duration: 2.0
        )
        #expect(result.uploadBandwidth > 0)
        #expect(result.averageWriteLatency >= 0)
        #expect(result.writeLatencyVariance >= 0)
        #expect(result.stabilityScore >= 0)
        #expect(result.stabilityScore <= 100)
        #expect(result.recommendedBitrate > 0)
        #expect(result.duration > 0)
    }

    // MARK: - Showcase 2: All fields present

    @Test("Probe result contains all expected fields")
    func probeResultContainsAllFields() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            duration: 2.0
        )

        // All numeric fields are non-negative
        #expect(result.uploadBandwidth >= 0)
        #expect(result.averageWriteLatency >= 0)
        #expect(result.writeLatencyVariance >= 0)
        #expect(result.stabilityScore >= 0)
        #expect(result.recommendedBitrate >= 0)
        #expect(result.duration >= 0)

        // Latency class is set
        _ = result.latencyClass
    }

    // MARK: - Showcase 3: ProbeTargetQuality thresholds

    @Test("ProbeTargetQuality.quality threshold (0.95) is highest")
    func probeTargetQualityThresholdRespected() {
        #expect(ProbeTargetQuality.quality.utilizationFactor == 0.95)
        #expect(ProbeTargetQuality.balanced.utilizationFactor == 0.85)
        #expect(ProbeTargetQuality.lowLatency.utilizationFactor == 0.70)
        #expect(
            ProbeTargetQuality.quality.utilizationFactor
                > ProbeTargetQuality.balanced.utilizationFactor
        )
    }

    // MARK: - Showcase 4: LatencyClass classification

    @Test("Probe classifies latency correctly into low/medium/high")
    func probeClassifiesLatencyCorrectly() {
        #expect(IcecastProbeResult.LatencyClass.classify(10) == .low)
        #expect(IcecastProbeResult.LatencyClass.classify(100) == .medium)
        #expect(IcecastProbeResult.LatencyClass.classify(300) == .high)
    }

    // MARK: - Showcase 5: Stability score reflects measurements

    @Test("Probe stability score is coherent with measured variance")
    func probeStabilityScoreReflectsVariance() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            duration: 2.0
        )
        // Mock writes are near-instant → very consistent → high stability
        #expect(result.stabilityScore >= 90)
    }

    // MARK: - Showcase 6: Connection failure

    @Test("Probe fails with connection error")
    func probeFailsWithConnectionError() async {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(host: "localhost", port: 8000, reason: "refused")
        )
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        await #expect(throws: IcecastError.self) {
            try await probe.measure(
                host: "localhost",
                mountpoint: "/probe",
                credentials: IcecastCredentials(password: "test"),
                duration: 2.0
            )
        }
    }

    // MARK: - Showcase 7: IcecastConfiguration.from(url:) with Icecast scheme

    @Test("IcecastConfiguration.from(url:) parses icecast:// scheme")
    func configurationFromIcecastURL() throws {
        let (config, creds) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@radio.example.com:8000/live.mp3"
        )
        #expect(config.host == "radio.example.com")
        #expect(config.port == 8000)
        #expect(config.mountpoint == "/live.mp3")
        #expect(creds.password == "hackme")
        #expect(creds.username == "source")
    }

    // MARK: - Showcase 8: IcecastConfiguration.from(url:) with SHOUTcast

    @Test("IcecastConfiguration.from(url:) parses shoutcast:// scheme")
    func configurationFromShoutcastURL() throws {
        let (config, creds) = try IcecastConfiguration.from(
            url: "shoutcast://djpass@sc.example.com:8000/"
        )
        #expect(config.protocolMode == .shoutcastV1)
        #expect(creds.password == "djpass")
        #expect(config.host == "sc.example.com")
    }

    // MARK: - Showcase 9: IcecastConfiguration.from(url:) invalid URL

    @Test("IcecastConfiguration.from(url:) throws for invalid URL")
    func configurationFromInvalidURL() {
        #expect(throws: IcecastError.self) {
            _ = try IcecastConfiguration.from(url: "ftp://bad.com/stream")
        }
    }

    // MARK: - Showcase 10: IcecastConfiguration.from(url:) missing credentials

    @Test("IcecastConfiguration.from(url:) throws without password")
    func configurationFromURLWithoutPassword() {
        #expect(throws: IcecastError.self) {
            _ = try IcecastConfiguration.from(url: "icecast://radio.example.com:8000/live.mp3")
        }
    }

    // MARK: - Showcase 11: Probe with AAC content type

    @Test("Probe with AAC content type returns valid AAC step")
    func probeWithAACContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            contentType: .aac,
            duration: 2.0
        )
        let validBitrates = AudioQualityStep.aacSteps.map(\.bitrate)
        #expect(validBitrates.contains(result.recommendedBitrate))
    }

    // MARK: - Showcase 12: from(url:) with default username

    @Test("IcecastConfiguration.from(url:) defaults to 'source' username")
    func configurationFromURLDefaultUsername() throws {
        let (_, creds) = try IcecastConfiguration.from(
            url: "icecast://:hackme@radio.example.com/live.mp3"
        )
        #expect(creds.username == "source")
    }

    // MARK: - Showcase 13: from(url:) with unparseable URL

    @Test("IcecastConfiguration.from(url:) throws for unparseable URL string")
    func configurationFromUnparseableURL() {
        #expect(throws: IcecastError.self) {
            _ = try IcecastConfiguration.from(url: "://")
        }
    }

    // MARK: - Showcase 14: from(url:) with missing host

    @Test("IcecastConfiguration.from(url:) throws for URL without host")
    func configurationFromURLWithoutHost() {
        #expect(throws: IcecastError.self) {
            _ = try IcecastConfiguration.from(url: "icecast:///live.mp3")
        }
    }
}
