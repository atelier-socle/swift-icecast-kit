// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - AudioChunk Tests

@Suite("AudioChunk")
struct AudioChunkTests {

    @Test("construction with all fields")
    func constructionAllFields() {
        let data = Data([0x01, 0x02, 0x03])
        let meta = ICYMetadata(streamTitle: "Test")
        let now = Date()
        let chunk = AudioChunk(
            data: data,
            metadata: meta,
            contentType: .mp3,
            timestamp: now,
            byteOffset: 100
        )
        #expect(chunk.data == data)
        #expect(chunk.metadata?.streamTitle == "Test")
        #expect(chunk.contentType == .mp3)
        #expect(chunk.timestamp == now)
        #expect(chunk.byteOffset == 100)
    }

    @Test("byteOffset grows correctly across chunks")
    func byteOffsetGrows() {
        let chunk1 = AudioChunk(
            data: Data(repeating: 0xAA, count: 100),
            contentType: .mp3,
            byteOffset: 100
        )
        let chunk2 = AudioChunk(
            data: Data(repeating: 0xBB, count: 50),
            contentType: .mp3,
            byteOffset: 150
        )
        #expect(chunk2.byteOffset > chunk1.byteOffset)
        #expect(chunk2.byteOffset == 150)
    }
}

// MARK: - IcecastRelay Tests

@Suite("IcecastRelay")
struct IcecastRelayTests {

    /// Builds a mock response + audio data for relay testing.
    private func buildRelayMock(
        audioChunks: [Data] = [Data(repeating: 0xAA, count: 50)]
    ) -> MockTransportConnection {
        let mock = MockTransportConnection()
        let headerResponse = Data(
            "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
        )
        Task {
            await mock.enqueueResponse(headerResponse)
            for chunk in audioChunks {
                await mock.enqueueResponse(chunk)
            }
        }
        return mock
    }

    @Test("connect starts reception")
    func connectStartsReception() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 50))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let isConn = await relay.isConnected
        #expect(isConn)
        await relay.disconnect()
    }

    @Test("audioStream emits chunks after connection")
    func audioStreamEmitsChunks() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 50))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()

        let task = Task<AudioChunk?, Never> {
            for await chunk in relay.audioStream {
                return chunk
            }
            return nil
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        let chunk = await task.value
        #expect(chunk != nil)
        #expect(chunk?.data.count == 50)
        #expect(chunk?.contentType == .mp3)
        await relay.disconnect()
        task.cancel()
    }

    @Test("isConnected reflects state")
    func isConnectedState() async throws {
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

        var isConn = await relay.isConnected
        #expect(!isConn)

        try await relay.connect()
        isConn = await relay.isConnected
        #expect(isConn)

        await relay.disconnect()
        isConn = await relay.isConnected
        #expect(!isConn)
    }

    @Test("bytesReceived grows correctly")
    func bytesReceivedGrows() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 100))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        try await Task.sleep(nanoseconds: 100_000_000)

        let received = await relay.bytesReceived
        #expect(received >= 100)
        await relay.disconnect()
    }

    @Test("disconnect terminates audioStream")
    func disconnectTerminatesStream() async throws {
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
        try await Task.sleep(nanoseconds: 50_000_000)
        await relay.disconnect()

        let terminated = Task<Bool, Never> {
            for await _ in relay.audioStream {}
            return true
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        terminated.cancel()
        let done = await terminated.value
        #expect(done)
    }

    @Test("RelayEvent.connected emitted on connection")
    func connectedEventEmitted() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\nServer: Icecast 2.4.4\r\n\r\n"
                    .utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        let task = Task<RelayEvent?, Never> {
            for await event in relay.events {
                if case .connected = event {
                    return event
                }
            }
            return nil
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await relay.connect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let event = await task.value
        if case .connected(let version, let ct) = event {
            #expect(version == "Icecast 2.4.4")
            #expect(ct == .mp3)
        } else {
            #expect(Bool(false), "Expected connected event")
        }
        await relay.disconnect()
    }

    @Test("RelayEvent.disconnected emitted on disconnect")
    func disconnectedEventEmitted() async throws {
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

        let task = Task<Bool, Never> {
            for await event in relay.events {
                if case .disconnected = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        await relay.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        let found = await task.value
        #expect(found)
    }

    @Test("RelayEvent.streamEnded emitted when server closes")
    func streamEndedEvent() async throws {
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

        let task = Task<Bool, Never> {
            for await event in relay.events {
                if case .streamEnded = event {
                    return true
                }
            }
            return false
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await relay.connect()
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        let found = await task.value
        #expect(found)
        await relay.disconnect()
    }

    @Test("connection failure throws relayConnectionFailed")
    func connectionFailure() async throws {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(host: "bad", port: 0, reason: "test")
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://bad:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    @Test("detectedContentType reflects HTTP headers")
    func detectedContentType() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/aac\r\n\r\n".utf8)
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

    @Test("serverVersion reflects HTTP headers")
    func serverVersionReflected() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\nServer: TestServer/1.0\r\n\r\n"
                    .utf8
            )
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
        let version = await relay.serverVersion
        #expect(version == "TestServer/1.0")
        await relay.disconnect()
    }
}
