// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for showcase test event assertions.
private actor ShowcaseEventCollector {
    var events: [ConnectionEvent] = []

    func append(_ event: ConnectionEvent) {
        events.append(event)
    }
}

@Suite("Showcase — Streaming Workflows")
struct StreamingShowcaseTests {

    // MARK: - Shared Helpers

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)
    private static let sourceOKResponse = Data("ICE/1.0 200 OK\r\n\r\n".utf8)
    private static let shoutcastOKResponse = Data("OK2\r\nicy-caps:11\r\n\r\n".utf8)

    private static func collectEvents(
        from client: IcecastClient,
        into collector: ShowcaseEventCollector
    ) -> Task<Void, Never> {
        Task {
            for await event in client.events {
                await collector.append(event)
            }
        }
    }

    /// Shared station info for PUT tests.
    private static let showcaseStationInfo = StationInfo(
        name: "Radio Showcase",
        description: "A showcase test station",
        url: "https://radio.example.com",
        genre: "Electronic",
        isPublic: true,
        bitrate: 128,
        sampleRate: 44100,
        channels: 2
    )

    /// Shared config for PUT tests.
    private static let showcaseConfig = IcecastConfiguration(
        host: "radio.example.com",
        port: 8000,
        mountpoint: "/live.mp3",
        stationInfo: showcaseStationInfo
    )

    // MARK: - Test 1a: Icecast PUT Streaming Lifecycle

    /// Demonstrates Icecast PUT streaming lifecycle:
    /// 1. Configure connection with full station info
    /// 2. Connect via PUT, send 480KB of audio, update metadata twice
    /// 3. Verify statistics and disconnect gracefully
    @Test("Icecast PUT streaming lifecycle")
    func icecastPUTStreamingLifecycle() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.showcaseConfig,
            credentials: IcecastCredentials(password: "hackme"),
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )

        try await client.connect()
        #expect(await client.state == .connected)

        // Send 30s of 128 kbps audio (480,000 bytes in 4KB chunks)
        let chunkSize = 4096
        let chunkCount = 480_000 / chunkSize
        for _ in 0..<chunkCount {
            try await client.send(Data(repeating: 0xFF, count: chunkSize))
        }
        #expect(await client.state == .streaming)

        // Update metadata twice
        try await client.updateMetadata(ICYMetadata(streamTitle: "Artist 1 - Song 1"))
        try await client.updateMetadata(ICYMetadata(streamTitle: "Artist 2 - Song 2"))

        // Verify statistics
        let stats = await client.statistics
        #expect(stats.bytesSent == UInt64(chunkCount * chunkSize))
        #expect(stats.metadataUpdateCount == 2)
        #expect(stats.connectedSince != nil)

        await client.disconnect()
        #expect(await client.state == .disconnected)
    }

    // MARK: - Test 1b: Icecast PUT Event Lifecycle

    /// Verifies the complete event sequence during PUT streaming:
    /// connected → protocolNegotiated(.icecastPUT) → metadataUpdated × 2 → disconnected
    @Test("Icecast PUT event sequence")
    func icecastPUTEventSequence() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.showcaseConfig,
            credentials: IcecastCredentials(password: "hackme"),
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        let collector = ShowcaseEventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)

        try await client.connect()
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song 1"))
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song 2"))
        await client.disconnect()

        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        let events = await collector.events
        #expect(
            events.contains {
                if case .connected = $0 { return true }
                return false
            })
        #expect(
            events.contains {
                if case .protocolNegotiated(.icecastPUT) = $0 { return true }
                return false
            })
        let metaCount = events.filter {
            if case .metadataUpdated = $0 { return true }
            return false
        }
        #expect(metaCount.count == 2)
        #expect(
            events.contains {
                if case .disconnected(.requested) = $0 { return true }
                return false
            })
    }

    // MARK: - Test 2: Legacy SOURCE Fallback

    /// Demonstrates automatic fallback from PUT to SOURCE:
    /// 1. Attempt PUT → server returns empty response (pre-2.4.0 server)
    /// 2. Negotiator detects failure, closes original connection
    /// 3. Creates a new connection and tries SOURCE protocol
    /// 4. SOURCE succeeds → client is connected
    /// 5. Send audio data → verify it's transmitted
    @Test("Legacy SOURCE protocol fallback")
    func legacySOURCEFallback() async throws {
        // Configuration uses .auto protocol mode (default)
        let configuration = IcecastConfiguration(
            host: "legacy.example.com",
            port: 8000,
            mountpoint: "/live.mp3"
        )
        let credentials = IcecastCredentials(password: "hackme")

        // Mock sequence: first connection returns empty (PUT fails),
        // second connection returns ICE/1.0 200 OK (SOURCE succeeds)
        let mock = MockTransportConnection()
        // PUT handshake will get empty response → triggers emptyResponse error
        await mock.enqueueResponse(Data())
        // After fallback: SOURCE handshake succeeds
        await mock.enqueueResponse(Self.sourceOKResponse)

        let client = IcecastClient(
            configuration: configuration,
            credentials: credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )

        let collector = ShowcaseEventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)

        try await client.connect()

        // Verify client is connected (negotiator fell back to SOURCE)
        let state = await client.state
        #expect(state == .connected)

        // Send audio data to verify streaming works
        let audioData = Data(repeating: 0xAA, count: 1024)
        try await client.send(audioData)
        let stateAfterSend = await client.state
        #expect(stateAfterSend == .streaming)

        // Verify bytes were recorded
        let stats = await client.statistics
        #expect(stats.bytesSent == 1024)

        await client.disconnect()

        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        // Verify SOURCE protocol was negotiated
        let events = await collector.events
        let sourceNegotiated = events.contains {
            if case .protocolNegotiated(.icecastSOURCE) = $0 { return true }
            return false
        }
        #expect(sourceNegotiated)
    }

    // MARK: - Test 3: SHOUTcast v1 Streaming

    /// Demonstrates SHOUTcast v1 authentication and streaming:
    /// 1. Connect to source port (listener port + 1)
    /// 2. Send password line
    /// 3. Receive OK2 + icy-caps
    /// 4. Send stream headers
    /// 5. Stream audio data
    @Test("SHOUTcast v1 streaming with password auth")
    func shoutcastV1Streaming() async throws {
        // Configure for SHOUTcast v1 with station info
        let stationInfo = StationInfo(
            name: "SHOUTcast Radio",
            genre: "Jazz",
            isPublic: true,
            bitrate: 128
        )
        let configuration = IcecastConfiguration(
            host: "shoutcast.example.com",
            port: 8000,
            mountpoint: "/stream",
            stationInfo: stationInfo,
            protocolMode: .shoutcastV1
        )
        let credentials = IcecastCredentials.shoutcast(password: "shoutpass")

        let mock = MockTransportConnection()
        // SHOUTcast v1 auth response: OK2 with capabilities
        await mock.enqueueResponse(Self.shoutcastOKResponse)

        let client = IcecastClient(
            configuration: configuration,
            credentials: credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )

        let collector = ShowcaseEventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)

        try await client.connect()
        let state = await client.state
        #expect(state == .connected)

        // Verify connection was made to source port (listener port + 1)
        let connectPort = await mock.lastConnectPort
        #expect(connectPort == 8001)

        // Verify sent data includes password line and stream headers
        let sentData = await mock.sentData
        #expect(sentData.count >= 2)  // password + headers

        // Verify the password was sent as the first line
        let firstSent = sentData[0]
        let passwordLine = String(decoding: firstSent, as: UTF8.self)
        #expect(passwordLine == "shoutpass\r\n")

        // Verify headers were sent (second sent data includes content-type)
        let headersSent = String(decoding: sentData[1], as: UTF8.self)
        #expect(headersSent.contains("content-type: audio/mpeg"))
        #expect(headersSent.contains("icy-name: SHOUTcast Radio"))

        // Send audio data
        let audioData = Data(repeating: 0xBB, count: 2048)
        try await client.send(audioData)
        let stats = await client.statistics
        #expect(stats.bytesSent == 2048)

        await client.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        // Verify SHOUTcast v1 protocol was negotiated
        let events = await collector.events
        #expect(
            events.contains {
                if case .protocolNegotiated(.shoutcastV1) = $0 { return true }
                return false
            })
    }

    // MARK: - Test 4: SHOUTcast v2 Multi-Stream

    /// Demonstrates SHOUTcast v2 with stream ID:
    /// 1. Connect with stream ID 3
    /// 2. Authenticate with "password:#3" format
    /// 3. Verify correct stream selection
    /// 4. Send audio → success
    @Test("SHOUTcast v2 multi-stream with stream ID")
    func shoutcastV2MultiStream() async throws {
        // Configure for SHOUTcast v2 with stream ID 3
        let configuration = IcecastConfiguration(
            host: "shoutcast.example.com",
            port: 8000,
            mountpoint: "/stream",
            stationInfo: StationInfo(name: "SHOUTcast v2 Radio", bitrate: 192),
            protocolMode: .shoutcastV2(streamId: 3)
        )
        let credentials = IcecastCredentials.shoutcast(password: "v2pass")

        let mock = MockTransportConnection()
        // SHOUTcast v2 uses same OK2 response format
        await mock.enqueueResponse(Self.shoutcastOKResponse)

        let client = IcecastClient(
            configuration: configuration,
            credentials: credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )

        let collector = ShowcaseEventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)

        try await client.connect()
        let state = await client.state
        #expect(state == .connected)

        // Verify connection on source port (listener port + 1)
        let connectPort = await mock.lastConnectPort
        #expect(connectPort == 8001)

        // Verify password format is "password:#streamId"
        let sentData = await mock.sentData
        let firstSent = String(decoding: sentData[0], as: UTF8.self)
        #expect(firstSent == "v2pass:#3\r\n")

        // Send audio data → verify success
        try await client.send(Data(repeating: 0xCC, count: 1024))
        let stats = await client.statistics
        #expect(stats.bytesSent == 1024)

        await client.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        // Verify SHOUTcast v2 protocol negotiated
        let events = await collector.events
        #expect(
            events.contains {
                if case .protocolNegotiated(.shoutcastV2(streamId: 3)) = $0 { return true }
                return false
            })
    }
}
