// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for testing async event streams.
actor EventCollector {
    var events: [ConnectionEvent] = []

    func append(_ event: ConnectionEvent) {
        events.append(event)
    }
}

@Suite("IcecastClient — Lifecycle")
struct IcecastClientLifecycleTests {

    // MARK: - Test Helpers

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)

    private static let testConfig = IcecastConfiguration(
        host: "radio.example.com",
        port: 8000,
        mountpoint: "/live.mp3"
    )

    private static let testCredentials = IcecastCredentials(password: "hackme")

    private static func makeClient(
        configuration: IcecastConfiguration = testConfig,
        credentials: IcecastCredentials = testCredentials,
        reconnectPolicy: ReconnectPolicy = .none,
        mock: MockTransportConnection
    ) -> IcecastClient {
        IcecastClient(
            configuration: configuration,
            credentials: credentials,
            reconnectPolicy: reconnectPolicy,
            connectionFactory: { mock }
        )
    }

    private static func collectEvents(
        from client: IcecastClient,
        into collector: EventCollector
    ) -> Task<Void, Never> {
        Task {
            for await event in client.events {
                await collector.append(event)
            }
        }
    }

    // MARK: - Connection Lifecycle

    @Test("connect transitions to connected state")
    func connectTransitionsToConnected() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        let state = await client.state
        #expect(state == .connected)
    }

    @Test("connect emits connected event")
    func connectEmitsConnectedEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = EventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .connected = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("connect emits protocolNegotiated event")
    func connectEmitsProtocolNegotiatedEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = EventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .protocolNegotiated = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("send transitions connected to streaming")
    func sendTransitionsToStreaming() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.send(Data("audio".utf8))
        let state = await client.state
        #expect(state == .streaming)
    }

    @Test("send records data on transport")
    func sendRecordsData() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        let audioData = Data("audio-frame".utf8)
        try await client.send(audioData)
        let sentData = await mock.sentData
        #expect(sentData.last == audioData)
    }

    @Test("disconnect transitions to disconnected state")
    func disconnectTransitions() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await client.disconnect()
        let state = await client.state
        #expect(state == .disconnected)
    }

    @Test("disconnect emits disconnected event with requested reason")
    func disconnectEmitsEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = EventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        await client.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .disconnected(let reason) = $0 { return reason == .requested }
            return false
        }
        #expect(found)
    }

    @Test("disconnect closes transport connection")
    func disconnectClosesTransport() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await client.disconnect()
        let closeCount = await mock.closeCallCount
        #expect(closeCount >= 1)
    }

    // MARK: - State Enforcement

    @Test("connect when already connected throws alreadyConnected")
    func connectWhenConnectedThrows() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponses([Self.putOKResponse, Self.putOKResponse])
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await #expect(throws: IcecastError.self) { try await client.connect() }
    }

    @Test("connect when streaming throws alreadyConnected")
    func connectWhenStreamingThrows() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.send(Data("audio".utf8))
        await #expect(throws: IcecastError.self) { try await client.connect() }
    }

    @Test("send when disconnected throws notConnected")
    func sendWhenDisconnectedThrows() async {
        let mock = MockTransportConnection()
        let client = Self.makeClient(mock: mock)
        await #expect(throws: IcecastError.self) { try await client.send(Data("audio".utf8)) }
    }

    @Test("send when connecting throws notConnected")
    func sendWhenConnectingThrows() async {
        let mock = MockTransportConnection()
        await mock.setConnectError(.connectionTimeout(seconds: 30))
        let client = Self.makeClient(mock: mock)
        try? await client.connect()
        await #expect(throws: IcecastError.self) { try await client.send(Data("audio".utf8)) }
    }

    @Test("disconnect when disconnected is a no-op")
    func disconnectWhenDisconnectedIsNoOp() async {
        let mock = MockTransportConnection()
        let client = Self.makeClient(mock: mock)
        await client.disconnect()
        let state = await client.state
        #expect(state == .disconnected)
    }

    @Test("updateConfiguration when connected is allowed")
    func updateConfigurationWhenConnected() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await client.updateConfiguration(IcecastConfiguration(host: "new.host.com", mountpoint: "/new.mp3"))
        let state = await client.state
        #expect(state == .connected)
    }

    // MARK: - Metadata Updates

    @Test("updateMetadata emits metadataUpdated event")
    func updateMetadataEmitsEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let collector = EventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)
        try await client.connect()
        try await client.updateMetadata(ICYMetadata(streamTitle: "Test Song"))
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()
        let events = await collector.events
        let found = events.contains {
            if case .metadataUpdated = $0 { return true }
            return false
        }
        #expect(found)
    }

    @Test("updateMetadata when not connected throws notConnected")
    func updateMetadataWhenDisconnectedThrows() async {
        let mock = MockTransportConnection()
        let client = Self.makeClient(mock: mock)
        await #expect(throws: IcecastError.self) {
            try await client.updateMetadata(ICYMetadata(streamTitle: "Test"))
        }
    }

    // MARK: - isConnected

    @Test("isConnected reflects connection state")
    func isConnectedReflectsState() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        let before = await client.isConnected
        #expect(!before)
        try await client.connect()
        let during = await client.isConnected
        #expect(during)
        await client.disconnect()
        let after = await client.isConnected
        #expect(!after)
    }

    // MARK: - Multiple Concurrent Sends

    @Test("Multiple concurrent send calls")
    func multipleConcurrentSends() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { try? await client.send(Data("frame-\(i)".utf8)) }
            }
        }
        let stats = await client.statistics
        #expect(stats.bytesSent > 0)
    }
}
