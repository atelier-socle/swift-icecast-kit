// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - IcecastRelay Coverage Tests

@Suite("IcecastRelay — Coverage")
struct IcecastRelayCoverageTests {

    @Test("currentMetadata returns nil before any metadata received")
    func currentMetadataInitiallyNil() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let meta = await relay.currentMetadata
        #expect(meta == nil)
        await relay.disconnect()
    }

    @Test("metadata updated when ICY metadata present in stream")
    func metadataUpdatedFromStream() async throws {
        let mock = MockTransportConnection()
        // Response with metaint = 10
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\nicy-metaint: 10\r\n\r\n"
                    .utf8
            )
        )
        // 10 bytes of audio
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))
        // metadata block: length byte = 2 (32 bytes), then StreamTitle
        var metaBlock = Data([2])  // 2 * 16 = 32 bytes
        let titleData = "StreamTitle='Test Song';".utf8
        metaBlock.append(contentsOf: titleData)
        // Pad to 32 bytes
        let padding = 32 - titleData.count
        metaBlock.append(Data(repeating: 0x00, count: padding))
        await mock.enqueueResponse(metaBlock)
        // More audio after metadata
        await mock.enqueueResponse(Data(repeating: 0xBB, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        let metaTask = Task<ICYMetadata?, Never> {
            for await event in relay.events {
                if case .metadataUpdated(let m) = event {
                    return m
                }
            }
            return nil
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await relay.connect()
        try await Task.sleep(nanoseconds: 200_000_000)
        metaTask.cancel()

        let received = await metaTask.value
        #expect(received?.streamTitle == "Test Song")
        await relay.disconnect()
    }

    @Test("resolveContentType maps audio/ogg to oggOpus")
    func audioOggContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/ogg\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.ogg"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let ct = await relay.detectedContentType
        #expect(ct == .oggOpus)
        await relay.disconnect()
    }

    @Test("resolveContentType maps application/ogg to oggVorbis")
    func applicationOggContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: application/ogg\r\n\r\n".utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.ogg"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let ct = await relay.detectedContentType
        #expect(ct == .oggVorbis)
        await relay.disconnect()
    }

    @Test("resolveContentType maps audio/aacp to aac")
    func audioAacpContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/aacp\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.aac"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let ct = await relay.detectedContentType
        #expect(ct == .aac)
        await relay.disconnect()
    }

    @Test("resolveContentType passes unknown type to AudioContentType init")
    func unknownContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/x-custom\r\n\r\n".utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let ct = await relay.detectedContentType
        // AudioContentType(rawValue:) creates a value from any raw string
        #expect(ct != nil)
        await relay.disconnect()
    }

    @Test("resolveContentType handles nil content-type header")
    func nilContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let ct = await relay.detectedContentType
        #expect(ct == nil)
        await relay.disconnect()
    }

    @Test("connect when already connected is a no-op")
    func connectWhenAlreadyConnected() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        // Second connect should be a no-op
        try await relay.connect()
        let isConn = await relay.isConnected
        #expect(isConn)
        await relay.disconnect()
    }

    @Test("disconnect when not connected is safe")
    func disconnectWhenNotConnected() async throws {
        let mock = MockTransportConnection()
        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        // Should not crash
        await relay.disconnect()
        let isConn = await relay.isConnected
        #expect(!isConn)
    }

    @Test("audio/mp3 content type resolves to mp3")
    func audioMp3ContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mp3\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let ct = await relay.detectedContentType
        #expect(ct == .mp3)
        await relay.disconnect()
    }
}

// MARK: - IcecastRelay Reconnection Tests

@Suite("IcecastRelay — Reconnection")
struct IcecastRelayReconnectionTests {

    @Test("reconnection triggered on stream end with policy")
    func reconnectionOnStreamEnd() async throws {
        let mock = MockTransportConnection()
        let headerData = Data(
            "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
        )
        await mock.enqueueResponse(headerData)
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let policy = ReconnectPolicy(
            maxRetries: 2,
            initialDelay: 0.05,
            maxDelay: 0.1,
            backoffMultiplier: 1.0,
            jitterFactor: 0.0
        )
        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            reconnectPolicy: policy
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        let eventTask = Task<[RelayEvent], Never> {
            var collected: [RelayEvent] = []
            for await event in relay.events {
                collected.append(event)
            }
            return collected
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await relay.connect()

        // Set onConnect handler AFTER initial connection so that
        // reconnection attempts re-enqueue fresh responses.
        await mock.setOnConnect { mock in
            await mock.enqueueResponse(headerData)
            await mock.enqueueResponse(Data(repeating: 0xBB, count: 10))
        }
        // Wait for stream end + reconnection + second stream end
        try await Task.sleep(nanoseconds: 800_000_000)
        eventTask.cancel()
        let events = await eventTask.value

        let hasStreamEnded = events.contains {
            if case .streamEnded = $0 { return true }
            return false
        }
        let hasReconnecting = events.contains {
            if case .reconnecting = $0 { return true }
            return false
        }
        let hasReconnected = events.contains {
            if case .reconnected = $0 { return true }
            return false
        }
        #expect(hasStreamEnded)
        #expect(hasReconnecting)
        #expect(hasReconnected)
        await relay.disconnect()
    }

    @Test("max retries exceeded emits disconnected with error")
    func maxRetriesExceeded() async throws {
        let mock = MockTransportConnection()
        let headerData = Data(
            "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
        )
        await mock.enqueueResponse(headerData)
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let policy = ReconnectPolicy(
            maxRetries: 2,
            initialDelay: 0.01,
            maxDelay: 0.02,
            backoffMultiplier: 1.0,
            jitterFactor: 0.0
        )
        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            reconnectPolicy: policy
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        let eventTask = Task<[RelayEvent], Never> {
            var collected: [RelayEvent] = []
            for await event in relay.events {
                collected.append(event)
            }
            return collected
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await relay.connect()

        // Make all reconnection attempts fail by setting a connect error
        // after the initial connection succeeds.
        await mock.setOnConnect { mock in
            await mock.setConnectError(
                .connectionFailed(
                    host: "localhost", port: 8000, reason: "refused"
                )
            )
        }

        // Wait for stream end + all retry attempts to exhaust
        try await Task.sleep(nanoseconds: 500_000_000)
        eventTask.cancel()
        let events = await eventTask.value

        let hasDisconnectedWithError = events.contains {
            if case .disconnected(let err) = $0 {
                return err != nil
            }
            return false
        }
        #expect(hasDisconnectedWithError)

        let isConn = await relay.isConnected
        #expect(!isConn)

        // audioStream should have terminated
        let streamTerminated = Task<Bool, Never> {
            for await _ in relay.audioStream {}
            return true
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        streamTerminated.cancel()
        let done = await streamTerminated.value
        #expect(done)

        await relay.disconnect()
    }
}
