// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Relay → Recording Chain Tests

@Suite("Relay → Recording Chain")
struct RelayRecordingChainTests {

    @Test("relay audioStream feeds StreamRecorder")
    func relayToRecorder() async throws {
        let dir = NSTemporaryDirectory() + "icecast-relay-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: dir) }

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

        let recConfig = RecordingConfiguration(
            directory: dir, contentType: .mp3
        )
        let recorder = StreamRecorder(configuration: recConfig)
        try await recorder.start()

        try await relay.connect()

        let task = Task {
            for await chunk in relay.audioStream {
                try await recorder.write(chunk.data)
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = await task.result

        let stats = try await recorder.stop()
        #expect(stats.bytesWritten >= 100)
        await relay.disconnect()
    }
}

// MARK: - Relay → Re-publish Chain Tests

@Suite("Relay → Re-publish Chain")
struct RelayRepublishChainTests {

    @Test("relay chunks re-published via IcecastClient")
    func relayToClient() async throws {
        let relayMock = MockTransportConnection()
        await relayMock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8)
        )
        await relayMock.enqueueResponse(Data(repeating: 0xBB, count: 50))

        let clientMock = MockTransportConnection()
        await clientMock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let relayConfig = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: relayConfig,
            transportFactory: { relayMock }
        )

        let clientConfig = IcecastConfiguration(
            host: "localhost", mountpoint: "/relay"
        )
        let client = IcecastClient(
            configuration: clientConfig,
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { clientMock }
        )

        try await client.connect()
        try await relay.connect()

        let task = Task {
            for await chunk in relay.audioStream {
                try? await client.send(chunk.data)
            }
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = await task.result

        let sentCount = await clientMock.sendCallCount
        #expect(sentCount >= 2)

        await relay.disconnect()
        await client.disconnect()
    }
}

// MARK: - IcecastRelayConfiguration Tests

@Suite("IcecastRelayConfiguration")
struct IcecastRelayConfigurationTests {

    @Test("default values")
    func defaultValues() {
        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        #expect(config.sourceURL == "http://localhost:8000/live.mp3")
        #expect(config.credentials == nil)
        #expect(config.requestICYMetadata)
        #expect(config.bufferSize == 65536)
        #expect(config.userAgent == "IcecastKit/0.3.0")
        #expect(config.reconnectPolicy == nil)
        #expect(config.connectionTimeout == 10.0)
    }

    @Test("custom values")
    func customValues() {
        let creds = IcecastCredentials(password: "secret")
        let policy = ReconnectPolicy.default
        let config = IcecastRelayConfiguration(
            sourceURL: "https://radio.example.com/live.aac",
            credentials: creds,
            requestICYMetadata: false,
            bufferSize: 32768,
            userAgent: "TestAgent/1.0",
            reconnectPolicy: policy,
            connectionTimeout: 30.0
        )
        #expect(config.sourceURL == "https://radio.example.com/live.aac")
        #expect(config.credentials != nil)
        #expect(!config.requestICYMetadata)
        #expect(config.bufferSize == 32768)
        #expect(config.userAgent == "TestAgent/1.0")
        #expect(config.reconnectPolicy != nil)
        #expect(config.connectionTimeout == 30.0)
    }
}

// MARK: - RelayEvent Tests

@Suite("RelayEvent")
struct RelayEventTests {

    @Test("connected event carries server info")
    func connectedEvent() {
        let event = RelayEvent.connected(
            serverVersion: "Icecast 2.4.4",
            contentType: .mp3
        )
        if case .connected(let version, let ct) = event {
            #expect(version == "Icecast 2.4.4")
            #expect(ct == .mp3)
        } else {
            #expect(Bool(false))
        }
    }

    @Test("disconnected event carries optional error")
    func disconnectedEvent() {
        let event = RelayEvent.disconnected(error: nil)
        if case .disconnected(let err) = event {
            #expect(err == nil)
        } else {
            #expect(Bool(false))
        }
    }

    @Test("metadataUpdated event carries metadata")
    func metadataUpdatedEvent() {
        let meta = ICYMetadata(streamTitle: "Test Song")
        let event = RelayEvent.metadataUpdated(meta)
        if case .metadataUpdated(let m) = event {
            #expect(m.streamTitle == "Test Song")
        } else {
            #expect(Bool(false))
        }
    }

    @Test("reconnecting event carries attempt number")
    func reconnectingEvent() {
        let event = RelayEvent.reconnecting(attempt: 3)
        if case .reconnecting(let attempt) = event {
            #expect(attempt == 3)
        } else {
            #expect(Bool(false))
        }
    }
}

// MARK: - IcecastError Relay Tests

@Suite("IcecastError — Relay")
struct IcecastErrorRelayTests {

    @Test("relayConnectionFailed description")
    func relayConnectionFailedDescription() {
        let error = IcecastError.relayConnectionFailed(
            url: "http://example.com/live",
            reason: "Connection refused"
        )
        let desc = error.description
        #expect(desc.contains("example.com/live"))
        #expect(desc.contains("Connection refused"))
    }

    @Test("relayStreamEnded description")
    func relayStreamEndedDescription() {
        let error = IcecastError.relayStreamEnded
        #expect(error.description.contains("ended"))
    }

    @Test("relayMetadataParsingFailed description")
    func relayMetadataParsingFailedDescription() {
        let error = IcecastError.relayMetadataParsingFailed
        #expect(error.description.contains("metadata"))
    }
}
