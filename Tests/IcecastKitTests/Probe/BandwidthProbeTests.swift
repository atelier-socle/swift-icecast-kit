// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - IcecastProbeResult Tests

@Suite("IcecastProbeResult")
struct IcecastProbeResultTests {

    @Test("Construction with all fields")
    func constructionAllFields() {
        let result = IcecastProbeResult(
            uploadBandwidth: 2_400_000,
            averageWriteLatency: 12.0,
            writeLatencyVariance: 3.0,
            stabilityScore: 94.0,
            recommendedBitrate: 320_000,
            latencyClass: .low,
            duration: 5.2,
            serverVersion: "Icecast 2.4.4"
        )
        #expect(result.uploadBandwidth == 2_400_000)
        #expect(result.averageWriteLatency == 12.0)
        #expect(result.writeLatencyVariance == 3.0)
        #expect(result.stabilityScore == 94.0)
        #expect(result.recommendedBitrate == 320_000)
        #expect(result.latencyClass == .low)
        #expect(result.duration == 5.2)
        #expect(result.serverVersion == "Icecast 2.4.4")
    }

    @Test("Construction with nil serverVersion")
    func constructionNilVersion() {
        let result = IcecastProbeResult(
            uploadBandwidth: 500_000,
            averageWriteLatency: 80.0,
            writeLatencyVariance: 20.0,
            stabilityScore: 75.0,
            recommendedBitrate: 128_000,
            latencyClass: .medium,
            duration: 3.0,
            serverVersion: nil
        )
        #expect(result.serverVersion == nil)
    }

    @Test("LatencyClass low classification — under 50ms")
    func latencyClassLow() {
        #expect(IcecastProbeResult.LatencyClass.classify(0) == .low)
        #expect(IcecastProbeResult.LatencyClass.classify(10) == .low)
        #expect(IcecastProbeResult.LatencyClass.classify(49.9) == .low)
    }

    @Test("LatencyClass medium classification — 50 to 200ms")
    func latencyClassMedium() {
        #expect(IcecastProbeResult.LatencyClass.classify(50) == .medium)
        #expect(IcecastProbeResult.LatencyClass.classify(100) == .medium)
        #expect(IcecastProbeResult.LatencyClass.classify(200) == .medium)
    }

    @Test("LatencyClass high classification — over 200ms")
    func latencyClassHigh() {
        #expect(IcecastProbeResult.LatencyClass.classify(200.1) == .high)
        #expect(IcecastProbeResult.LatencyClass.classify(500) == .high)
        #expect(IcecastProbeResult.LatencyClass.classify(1000) == .high)
    }

    @Test("stabilityScore is within 0 to 100 range")
    func stabilityScoreRange() {
        let result = IcecastProbeResult(
            uploadBandwidth: 1_000_000,
            averageWriteLatency: 10.0,
            writeLatencyVariance: 5.0,
            stabilityScore: 50.0,
            recommendedBitrate: 128_000,
            latencyClass: .low,
            duration: 5.0,
            serverVersion: nil
        )
        #expect(result.stabilityScore >= 0)
        #expect(result.stabilityScore <= 100)
    }
}

// MARK: - ProbeTargetQuality Tests

@Suite("ProbeTargetQuality")
struct ProbeTargetQualityTests {

    @Test("utilizationFactor for quality is 0.95")
    func qualityFactor() {
        #expect(ProbeTargetQuality.quality.utilizationFactor == 0.95)
    }

    @Test("utilizationFactor for balanced is 0.85")
    func balancedFactor() {
        #expect(ProbeTargetQuality.balanced.utilizationFactor == 0.85)
    }

    @Test("utilizationFactor for lowLatency is 0.70")
    func lowLatencyFactor() {
        #expect(ProbeTargetQuality.lowLatency.utilizationFactor == 0.70)
    }

    @Test("CaseIterable covers all cases")
    func caseIterableCoversAll() {
        let cases = ProbeTargetQuality.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.quality))
        #expect(cases.contains(.balanced))
        #expect(cases.contains(.lowLatency))
    }

    @Test("quality factor is higher than balanced")
    func qualityHigherThanBalanced() {
        #expect(
            ProbeTargetQuality.quality.utilizationFactor
                > ProbeTargetQuality.balanced.utilizationFactor
        )
    }

    @Test("balanced factor is higher than lowLatency")
    func balancedHigherThanLowLatency() {
        #expect(
            ProbeTargetQuality.balanced.utilizationFactor
                > ProbeTargetQuality.lowLatency.utilizationFactor
        )
    }
}

// MARK: - IcecastBandwidthProbe Tests

@Suite("IcecastBandwidthProbe")
struct IcecastBandwidthProbeTests {

    @Test("Probe on fast mock connection returns coherent result")
    func probeCoherentResult() async throws {
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
        #expect(result.uploadBandwidth > 0)
        #expect(result.stabilityScore >= 0)
        #expect(result.stabilityScore <= 100)
        #expect(result.recommendedBitrate > 0)
    }

    @Test("Probe short duration (2s) returns valid result")
    func probeShortDuration() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            duration: 2.0
        )
        #expect(result.uploadBandwidth > 0)
        #expect(result.duration > 0)
    }

    @Test("recommendedBitrate is a valid AudioQualityStep for MP3")
    func recommendedBitrateIsValidStep() async throws {
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
        let validBitrates = AudioQualityStep.mp3Steps.map(\.bitrate)
        #expect(validBitrates.contains(result.recommendedBitrate))
    }

    @Test("recommendedBitrate does not exceed uploadBandwidth * 0.95")
    func recommendedBitrateWithinBandwidth() async throws {
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
        #expect(Double(result.recommendedBitrate) <= result.uploadBandwidth * 0.95)
    }

    @Test("Connection failure throws probeFailed")
    func connectionFailure() async {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(
                host: "localhost", port: 8000, reason: "refused"
            )
        )
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        await #expect(throws: IcecastError.self) {
            try await probe.measure(
                host: "localhost",
                port: 8000,
                mountpoint: "/probe",
                credentials: IcecastCredentials(password: "test"),
                duration: 2.0
            )
        }
    }

    @Test("Clean disconnect guaranteed even on server drop")
    func cleanDisconnectOnDrop() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        // Set send error to simulate server drop during probe
        await mock.setSendError(
            .connectionLost(reason: "reset")
        )
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        do {
            _ = try await probe.measure(
                host: "localhost",
                port: 8000,
                mountpoint: "/probe",
                credentials: IcecastCredentials(password: "test"),
                duration: 2.0
            )
        } catch {
            // Expected — probe should fail
        }
        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 50_000_000)
        let closeCount = await mock.closeCallCount
        #expect(closeCount >= 1)
    }

    @Test("duration in result reflects actual time")
    func durationReflectsActual() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            duration: 2.0
        )
        // Actual duration should be > 0 and reasonable
        #expect(result.duration > 0)
    }

    @Test("averageWriteLatency and writeLatencyVariance are coherent")
    func latencyMetricsCoherent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            duration: 2.0
        )
        #expect(result.averageWriteLatency >= 0)
        #expect(result.writeLatencyVariance >= 0)
    }

    @Test("Probe with AAC content type returns valid AAC step")
    func probeAAC() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            contentType: .aac,
            duration: 2.0
        )
        let validBitrates = AudioQualityStep.aacSteps.map(\.bitrate)
        #expect(validBitrates.contains(result.recommendedBitrate))
    }

    @Test("latencyClass matches averageWriteLatency")
    func latencyClassMatchesAverage() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            duration: 2.0
        )
        let expected = IcecastProbeResult.LatencyClass.classify(
            result.averageWriteLatency
        )
        #expect(result.latencyClass == expected)
    }

    @Test("Default public init creates a valid probe")
    func defaultPublicInit() {
        let probe = IcecastBandwidthProbe()
        _ = probe
    }

    @Test("Probe with Ogg Vorbis uses generic silence frame")
    func probeOggVorbis() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        let result = try await probe.measure(
            host: "localhost",
            port: 8000,
            mountpoint: "/probe",
            credentials: IcecastCredentials(password: "test"),
            contentType: .oggVorbis,
            duration: 2.0
        )
        let validBitrates = AudioQualityStep.vorbisSteps.map(\.bitrate)
        #expect(validBitrates.contains(result.recommendedBitrate))
        #expect(result.uploadBandwidth > 0)
    }

    @Test("Send failure during ramp throws probeFailed and cleans up")
    func rampSendFailure() async throws {
        let mock = FailAfterNSendsMock(failAfterSend: 1)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let probe = IcecastBandwidthProbe(connectionFactory: { mock })
        await #expect(throws: IcecastError.self) {
            try await probe.measure(
                host: "localhost",
                port: 8000,
                mountpoint: "/probe",
                credentials: IcecastCredentials(password: "test"),
                duration: 2.0
            )
        }
        let closeCount = await mock.closeCallCount
        #expect(closeCount >= 1)
    }
}

// MARK: - FailAfterNSendsMock

/// A mock transport that succeeds for the first N sends, then fails.
///
/// Used to test ramp failure paths where negotiation succeeds
/// but subsequent data writes fail.
actor FailAfterNSendsMock: TransportConnection {

    private let failAfterSend: Int
    private var sendCount: Int = 0
    private var receiveQueue: [Data] = []
    private var connected: Bool = false
    private(set) var closeCallCount: Int = 0

    init(failAfterSend: Int) {
        self.failAfterSend = failAfterSend
    }

    func enqueueResponse(_ response: Data) {
        receiveQueue.append(response)
    }

    var isConnected: Bool { connected }

    func connect(host: String, port: Int, useTLS: Bool) async throws {
        connected = true
    }

    func send(_ data: Data) async throws {
        sendCount += 1
        if sendCount > failAfterSend {
            throw IcecastError.connectionLost(reason: "simulated ramp failure")
        }
    }

    func receive(maxBytes: Int) async throws -> Data {
        guard !receiveQueue.isEmpty else {
            throw IcecastError.connectionLost(reason: "No more queued responses")
        }
        let data = receiveQueue.removeFirst()
        if data.count > maxBytes {
            return data.prefix(maxBytes)
        }
        return data
    }

    func receive(maxBytes: Int, timeout: TimeInterval) async throws -> Data {
        try await receive(maxBytes: maxBytes)
    }

    func close() async {
        closeCallCount += 1
        connected = false
    }
}
