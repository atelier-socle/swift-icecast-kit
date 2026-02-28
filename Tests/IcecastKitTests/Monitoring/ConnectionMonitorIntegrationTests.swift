// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for integration tests.
private actor IntegrationEventCollector {
    var events: [ConnectionEvent] = []

    func append(_ event: ConnectionEvent) {
        events.append(event)
    }
}

@Suite("ConnectionMonitor — Integration with IcecastClient")
struct ConnectionMonitorIntegrationTests {

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)

    private static let testConfig = IcecastConfiguration(
        host: "radio.example.com",
        port: 8000,
        mountpoint: "/live.mp3"
    )

    private static let testCredentials = IcecastCredentials(password: "hackme")

    private static func makeClient(
        reconnectPolicy: ReconnectPolicy = .none,
        mock: MockTransportConnection
    ) -> IcecastClient {
        IcecastClient(
            configuration: testConfig,
            credentials: testCredentials,
            reconnectPolicy: reconnectPolicy,
            connectionFactory: { mock }
        )
    }

    private static func collectEvents(
        from client: IcecastClient,
        into collector: IntegrationEventCollector
    ) -> Task<Void, Never> {
        Task {
            for await event in client.events {
                await collector.append(event)
            }
        }
    }

    // MARK: - Event Flow Through Client

    @Test("client.connect emits connected event via monitor")
    func connectEmitsConnectedViaMonitor() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .connected = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("client.connect emits protocolNegotiated event via monitor")
    func connectEmitsProtocolNegotiatedViaMonitor() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .protocolNegotiated = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("client.send updates monitor statistics bytesSent")
    func sendUpdatesBytesSent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.send(Data(repeating: 0xAA, count: 100))
        try await client.send(Data(repeating: 0xBB, count: 200))
        let stats = await client.statistics
        #expect(stats.bytesSent == 300)
    }

    @Test("client.updateMetadata emits metadataUpdated event via monitor")
    func updateMetadataEmitsEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await client.updateMetadata(ICYMetadata(streamTitle: "Test Song"))
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .metadataUpdated = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("client.disconnect emits disconnected event via monitor")
    func disconnectEmitsEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        await client.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .disconnected(let reason) = $0 { return reason == .requested }
            return false
        }
        #expect(found)
    }

    @Test("Authentication failure emits error event via monitor")
    func authFailureEmitsErrorEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try? await client.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .error = $0 { return true }
            return false
        }
        #expect(found)
    }

    // MARK: - Statistics Via Client

    @Test("client.statistics returns monitor statistics")
    func clientStatisticsReturnsMonitorStats() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        let stats = await client.statistics
        #expect(stats.connectedSince != nil)
    }

    @Test("client.statistics.bytesSent matches total data sent")
    func bytesSentMatchesTotalDataSent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.send(Data(repeating: 0x01, count: 50))
        try await client.send(Data(repeating: 0x02, count: 75))
        try await client.send(Data(repeating: 0x03, count: 25))
        let stats = await client.statistics
        #expect(stats.bytesSent == 150)
    }

    @Test("client.statistics.metadataUpdateCount matches metadata calls")
    func metadataUpdateCountMatchesCalls() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song 1"))
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song 2"))
        let stats = await client.statistics
        #expect(stats.metadataUpdateCount == 2)
    }

    @Test("client.statistics.sendErrorCount increments on send failures")
    func sendErrorCountIncrements() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await mock.setSendError(.sendFailed(reason: "pipe broken"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        let stats = await client.statistics
        #expect(stats.sendErrorCount == 1)
    }

    // MARK: - Event Stream Via Client

    @Test("client.events is the monitor event stream")
    func clientEventsIsMonitorStream() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        #expect(!events.isEmpty)
    }

    @Test("Event ordering preserved through client")
    func eventOrderingPreserved() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song"))
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let events = await collector.events
        var seenConnected = false
        var seenProtocol = false
        var metadataAfterConnect = false
        for event in events {
            if case .connected = event { seenConnected = true }
            if case .protocolNegotiated = event { seenProtocol = true }
            if case .metadataUpdated = event {
                if seenConnected && seenProtocol { metadataAfterConnect = true }
            }
        }
        #expect(seenConnected)
        #expect(seenProtocol)
        #expect(metadataAfterConnect)
    }

    // MARK: - Periodic Stats Via Client

    @Test("Periodic statistics events stop after disconnect")
    func periodicStatsStopAfterDisconnect() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        try await client.connect()
        await client.disconnect()
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let events = await collector.events
        let statsEvents = events.filter {
            if case .statistics = $0 { return true }
            return false
        }
        #expect(statsEvents.isEmpty)
    }

    // MARK: - Monitor Access

    @Test("client.monitor is accessible and returns statistics")
    func clientMonitorAccessible() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        let monitorStats = await client.monitor.statistics
        #expect(monitorStats.connectedSince != nil)
    }

    @Test("client.monitor.statistics matches client.statistics")
    func monitorStatsMatchClientStats() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.send(Data(repeating: 0xFF, count: 256))
        let clientStats = await client.statistics
        let monitorStats = await client.monitor.statistics
        #expect(clientStats.bytesSent == monitorStats.bytesSent)
        #expect(clientStats.metadataUpdateCount == monitorStats.metadataUpdateCount)
    }

    @Test("Connection loss triggers reconnecting events via monitor")
    func connectionLossTriggersReconnectingEvents() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponses([Self.putOKResponse, Self.putOKResponse])
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 2, initialDelay: 0.05, jitterFactor: 0.0),
            connectionFactory: { mock }
        )
        let collector = IntegrationEventCollector()
        let task = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        await mock.setSendError(.connectionLost(reason: "broken pipe"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .reconnecting = $0 { return true }
            return false
        }
        #expect(found)
    }
}
