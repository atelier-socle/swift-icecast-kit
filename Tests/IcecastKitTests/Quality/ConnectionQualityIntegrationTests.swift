// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - IcecastClient Integration Tests

@Suite("ConnectionQuality — IcecastClient Integration")
struct ConnectionQualityClientTests {

    @Test("connectionQuality returns nil when not connected")
    func qualityNilWhenDisconnected() async {
        let mock = MockTransportConnection()
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )
        let quality = await client.connectionQuality
        #expect(quality == nil)
    }

    @Test("qualityChanged event emitted with periodic statistics")
    func qualityChangedEmitted() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test"
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )

        try await client.connect()

        let task = Task<Bool, Never> {
            for await event in client.events {
                if case .qualityChanged = event {
                    return true
                }
            }
            return false
        }

        try await client.send(Data([0x00, 0x01]))
        try await Task.sleep(nanoseconds: 6_000_000_000)
        task.cancel()
        let found = await task.value
        #expect(found)
    }

    @Test("qualityWarning emitted when grade transitions to poor")
    func qualityWarningOnPoor() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.1)
        await monitor.markConnected()

        let task = Task<Bool, Never> {
            for await event in monitor.events {
                if case .qualityWarning = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        for _ in 0..<100 {
            await monitor.recordSendError()
        }
        for _ in 0..<5 {
            await monitor.recordSendLatency(600.0)
        }
        for _ in 0..<5 {
            await monitor.recordReconnection()
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let found = await task.value
        #expect(found)
    }

    @Test("No qualityWarning when grade transitions from good to excellent")
    func noWarningOnImprovement() async throws {
        let monitor = ConnectionMonitor(statisticsInterval: 0.1)
        await monitor.markConnected()

        let task = Task<Bool, Never> {
            for await event in monitor.events {
                if case .qualityWarning = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let found = await task.value
        #expect(!found)
    }
}

// MARK: - MultiIcecastClient Integration Tests

@Suite("ConnectionQuality — MultiIcecastClient Integration")
struct ConnectionQualityMultiClientTests {

    @Test("connectionQualities returns empty dict when no destinations connected")
    func qualitiesEmptyWhenNone() async {
        let multi = MultiIcecastClient()
        let qualities = await multi.connectionQualities
        #expect(qualities.isEmpty)
    }

    @Test("aggregatedQuality returns nil when no destinations connected")
    func aggregatedNilWhenNone() async {
        let multi = MultiIcecastClient()
        let quality = await multi.aggregatedQuality
        #expect(quality == nil)
    }

    @Test("connectionQualities returns per-destination quality when connected")
    func qualitiesPerDestination() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/test",
            credentials: IcecastCredentials(password: "test")
        )
        try await multi.addDestination("primary", configuration: config)
        try await multi.connectAll()

        let qualities = await multi.connectionQualities
        #expect(qualities["primary"] != nil)
        #expect(qualities["primary"]?.score ?? 0 > 0)
    }

    @Test("aggregatedQuality averages across connected destinations")
    func aggregatedQualityAverages() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })

        let config1 = IcecastConfiguration(
            host: "localhost", mountpoint: "/test1",
            credentials: IcecastCredentials(password: "test")
        )
        let config2 = IcecastConfiguration(
            host: "localhost", mountpoint: "/test2",
            credentials: IcecastCredentials(password: "test")
        )
        try await multi.addDestination("primary", configuration: config1)
        try await multi.addDestination("backup", configuration: config2)
        try await multi.connectAll()

        let aggregated = await multi.aggregatedQuality
        #expect(aggregated != nil)
        #expect(aggregated?.score ?? 0 > 0)
    }
}

// MARK: - ConnectionStatistics New Fields Tests

@Suite("ConnectionStatistics — Quality Fields")
struct ConnectionStatisticsQualityTests {

    @Test("New fields have correct defaults")
    func defaultValues() {
        let stats = ConnectionStatistics()
        #expect(stats.averageWriteLatency == 0)
        #expect(stats.writeLatencyVariance == 0)
        #expect(stats.totalSendCount == 0)
    }

    @Test("New fields can be set via initializer")
    func customValues() {
        let stats = ConnectionStatistics(
            averageWriteLatency: 15.0,
            writeLatencyVariance: 3.0,
            totalSendCount: 500
        )
        #expect(stats.averageWriteLatency == 15.0)
        #expect(stats.writeLatencyVariance == 3.0)
        #expect(stats.totalSendCount == 500)
    }

    @Test("ConnectionMonitor tracks send latency via Welford algorithm")
    func monitorTracksLatency() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.markConnected()
        await monitor.recordBytesSent(100)
        await monitor.recordSendLatency(10.0)
        await monitor.recordBytesSent(100)
        await monitor.recordSendLatency(20.0)
        await monitor.recordBytesSent(100)
        await monitor.recordSendLatency(30.0)

        let stats = await monitor.statistics
        #expect(stats.averageWriteLatency >= 19.9)
        #expect(stats.averageWriteLatency <= 20.1)
        #expect(stats.writeLatencyVariance > 0)
        #expect(stats.totalSendCount == 3)
    }

    @Test("ConnectionMonitor reset clears latency tracking")
    func monitorResetClearsLatency() async {
        let monitor = ConnectionMonitor(statisticsInterval: nil)
        await monitor.recordSendLatency(50.0)
        await monitor.recordSendLatency(60.0)
        await monitor.reset()

        let stats = await monitor.statistics
        #expect(stats.averageWriteLatency == 0)
        #expect(stats.writeLatencyVariance == 0)
        #expect(stats.totalSendCount == 0)
    }
}
