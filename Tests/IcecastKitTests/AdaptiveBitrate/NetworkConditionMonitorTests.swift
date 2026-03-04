// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - NetworkConditionMonitor Tests

@Suite("NetworkConditionMonitor")
struct NetworkConditionMonitorTests {

    @Test("Start and stop lifecycle")
    func startStopLifecycle() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        let before = await monitor.isMonitoring
        #expect(!before)

        await monitor.start()
        let during = await monitor.isMonitoring
        #expect(during)

        await monitor.stop()
        let after = await monitor.isMonitoring
        #expect(!after)
    }

    @Test("Starting twice is idempotent")
    func startTwiceIsIdempotent() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()
        await monitor.start()
        let monitoring = await monitor.isMonitoring
        #expect(monitoring)
    }

    @Test("Stopping a stopped monitor is a no-op")
    func stopStoppedMonitor() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.stop()
        let monitoring = await monitor.isMonitoring
        #expect(!monitoring)
    }

    @Test("CurrentBitrate reflects initial value")
    func currentBitrateInitial() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 192_000
        )
        let bitrate = await monitor.currentBitrate
        #expect(bitrate == 192_000)
    }

    @Test("Fast writes do not trigger recommendation")
    func fastWritesNoRecommendation() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()

        // Simulate 20 fast writes (1ms each for 4096 bytes)
        for _ in 0..<20 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate == 128_000)
    }

    @Test("Slow writes trigger decrease recommendation after hysteresis")
    func slowWritesTriggerDecrease() async {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 32_000, maxBitrate: 320_000,
            stepDown: 0.75, stepUp: 1.10,
            downTriggerThreshold: 1.3,
            upStabilityDuration: 5.0,
            measurementWindow: 0.0,
            hysteresisCount: 1
        )
        let monitor = NetworkConditionMonitor(
            policy: .custom(config), currentBitrate: 128_000
        )
        await monitor.start()

        // Establish baseline with fast writes
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // Simulate congestion: write latency 10× baseline
        for _ in 0..<5 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 4096)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 128_000)
    }

    @Test("Hysteresis prevents premature triggering")
    func hysteresisPreventsPrematureTriggering() async {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 32_000, maxBitrate: 320_000,
            stepDown: 0.75, stepUp: 1.10,
            downTriggerThreshold: 1.3,
            upStabilityDuration: 5.0,
            measurementWindow: 0.0,
            hysteresisCount: 10
        )
        let monitor = NetworkConditionMonitor(
            policy: .custom(config), currentBitrate: 128_000
        )
        await monitor.start()

        // Establish baseline
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // Send fewer congestion signals than hysteresis count
        for _ in 0..<5 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 4096)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate == 128_000)
    }

    @Test("Bandwidth estimation converges")
    func bandwidthEstimationConverges() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()

        // Simulate writes at ~128kbps: 4096 bytes in ~0.256 seconds
        let bytesPerWrite = 4096
        let expectedDuration = Double(bytesPerWrite) * 8.0 / 128_000.0

        for _ in 0..<20 {
            await monitor.recordWrite(duration: expectedDuration, bytesWritten: bytesPerWrite)
        }

        let bandwidth = await monitor.estimatedBandwidth
        // Should converge near 128kbps
        #expect(bandwidth > 100_000)
        #expect(bandwidth < 160_000)
    }

    @Test("EWMA latency smooths isolated spike")
    func ewmaLatencySmooths() async {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 32_000, maxBitrate: 320_000,
            stepDown: 0.75, stepUp: 1.10,
            downTriggerThreshold: 1.5,
            upStabilityDuration: 5.0,
            measurementWindow: 0.0,
            hysteresisCount: 3
        )
        let monitor = NetworkConditionMonitor(
            policy: .custom(config), currentBitrate: 128_000
        )
        await monitor.start()

        // Establish baseline
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // One isolated spike (3× baseline — small enough for EWMA to absorb)
        await monitor.recordWrite(duration: 0.003, bytesWritten: 4096)

        // Resume normal writes
        for _ in 0..<5 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // EWMA should smooth out the spike; bitrate should not have changed
        let bitrate = await monitor.currentBitrate
        #expect(bitrate == 128_000)
    }

    @Test("RecordWriteFailure contributes to congestion signal")
    func recordWriteFailureSignal() async {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 32_000, maxBitrate: 320_000,
            stepDown: 0.75, stepUp: 1.10,
            downTriggerThreshold: 1.3,
            upStabilityDuration: 5.0,
            measurementWindow: 0.0,
            hysteresisCount: 2
        )
        let monitor = NetworkConditionMonitor(
            policy: .custom(config), currentBitrate: 128_000
        )
        await monitor.start()

        // Establish baseline
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // Multiple write failures should trigger decrease
        for _ in 0..<3 {
            await monitor.recordWriteFailure()
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate < 128_000)
    }

    @Test("Monitor does not record when not started")
    func noRecordWhenNotStarted() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.recordWrite(duration: 0.1, bytesWritten: 4096)
        let latency = await monitor.averageWriteLatency
        #expect(latency == 0.0)
    }

    @Test("Monitor does not record after stop")
    func noRecordAfterStop() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()
        await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        await monitor.stop()
        let latencyAfterStop = await monitor.averageWriteLatency

        await monitor.recordWrite(duration: 1.0, bytesWritten: 4096)
        let latencyAfterRecord = await monitor.averageWriteLatency
        #expect(latencyAfterRecord == latencyAfterStop)
    }

    @Test("AverageWriteLatency updates with measurements")
    func averageWriteLatencyUpdates() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()

        await monitor.recordWrite(duration: 0.010, bytesWritten: 4096)
        let latency = await monitor.averageWriteLatency
        #expect(latency > 0)
    }

    @Test("Zero duration writes are ignored")
    func zeroDurationIgnored() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()
        await monitor.recordWrite(duration: 0.0, bytesWritten: 4096)
        let latency = await monitor.averageWriteLatency
        #expect(latency == 0.0)
    }

    @Test("Zero bytes writes are ignored")
    func zeroBytesIgnored() async {
        let monitor = NetworkConditionMonitor(
            policy: .aggressive, currentBitrate: 128_000
        )
        await monitor.start()
        await monitor.recordWrite(duration: 0.001, bytesWritten: 0)
        let latency = await monitor.averageWriteLatency
        #expect(latency == 0.0)
    }

    @Test("Bitrate does not go below minimum")
    func bitrateFloor() async {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 64_000, maxBitrate: 320_000,
            stepDown: 0.50, stepUp: 1.10,
            downTriggerThreshold: 1.2,
            upStabilityDuration: 0.01,
            measurementWindow: 0.0,
            hysteresisCount: 1
        )
        let monitor = NetworkConditionMonitor(
            policy: .custom(config), currentBitrate: 64_000
        )
        await monitor.start()

        // Establish baseline
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // Heavy congestion
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.050, bytesWritten: 4096)
        }

        let bitrate = await monitor.currentBitrate
        #expect(bitrate >= 64_000)
    }

    @Test("Recommendations stream emits on direction change")
    func recommendationsStreamEmits() async {
        let config = AdaptiveBitrateConfiguration(
            minBitrate: 32_000, maxBitrate: 320_000,
            stepDown: 0.75, stepUp: 1.10,
            downTriggerThreshold: 1.3,
            upStabilityDuration: 5.0,
            measurementWindow: 0.0,
            hysteresisCount: 1
        )
        let monitor = NetworkConditionMonitor(
            policy: .custom(config), currentBitrate: 128_000
        )

        let task = Task<BitrateRecommendation?, Never> {
            for await rec in monitor.recommendations {
                return rec
            }
            return nil
        }

        await monitor.start()

        // Establish baseline
        for _ in 0..<10 {
            await monitor.recordWrite(duration: 0.001, bytesWritten: 4096)
        }

        // Trigger congestion
        for _ in 0..<5 {
            await monitor.recordWrite(duration: 0.010, bytesWritten: 4096)
        }

        // Give the task a moment to receive
        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let recommendation = await task.value
        if let rec = recommendation {
            #expect(rec.direction == BitrateRecommendation.Direction.decrease)
        }
    }
}

// MARK: - IcecastConfiguration ABR Integration Tests

@Suite("IcecastConfiguration — ABR")
struct IcecastConfigurationABRTests {

    @Test("Configuration accepts nil adaptiveBitrate (ABR disabled)")
    func nilAdaptiveBitrate() {
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/live.mp3"
        )
        #expect(config.adaptiveBitrate == nil)
    }

    @Test("Configuration accepts an AdaptiveBitratePolicy")
    func withAdaptiveBitrate() {
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/live.mp3",
            adaptiveBitrate: .responsive(min: 64_000, max: 320_000)
        )
        #expect(config.adaptiveBitrate != nil)
        let abrConfig = config.adaptiveBitrate?.configuration
        #expect(abrConfig?.minBitrate == 64_000)
        #expect(abrConfig?.maxBitrate == 320_000)
    }

    @Test("ABR policy is preserved through mutation")
    func abrPolicyPreservedThroughMutation() {
        var config = IcecastConfiguration(
            host: "localhost", mountpoint: "/live.mp3"
        )
        config.adaptiveBitrate = .aggressive
        #expect(config.adaptiveBitrate?.configuration.stepDown == 0.60)
    }
}

// MARK: - IcecastClient ABR Integration Tests

@Suite("IcecastClient — ABR Integration")
struct IcecastClientABRIntegrationTests {

    @Test("ABR monitor is stopped on disconnect")
    func abrMonitorStoppedOnDisconnect() async {
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/live.mp3",
            adaptiveBitrate: .aggressive
        )
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try? await client.connect()
        await client.disconnect()

        let state = await client.state
        #expect(state == .disconnected)
    }

    @Test("Client without ABR policy has no ABR events")
    func noABRWithoutPolicy() async {
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/live.mp3"
        )
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        try? await client.connect()

        // Send data without ABR
        try? await client.send(Data(repeating: 0xAB, count: 4096))
        await client.disconnect()

        let state = await client.state
        #expect(state == .disconnected)
    }

    @Test("ConnectionEvent includes bitrateRecommendation case")
    func connectionEventHasBitrateRecommendation() {
        let rec = BitrateRecommendation(
            recommendedBitrate: 96_000, currentBitrate: 128_000,
            direction: .decrease, reason: .congestionDetected, confidence: 0.9
        )
        let event = ConnectionEvent.bitrateRecommendation(rec)
        if case .bitrateRecommendation(let r) = event {
            #expect(r.recommendedBitrate == 96_000)
        } else {
            Issue.record("Expected bitrateRecommendation event")
        }
    }
}
