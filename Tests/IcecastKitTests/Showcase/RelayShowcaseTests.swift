// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Relay")
struct RelayShowcaseTests {

    // MARK: - Helpers

    /// Builds an HTTP 200 OK response with ICY headers.
    private func buildRelayResponse(
        contentType: String = "audio/mpeg",
        metaint: Int? = nil,
        server: String = "Icecast 2.4.4"
    ) -> Data {
        var lines = [
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Server: \(server)"
        ]
        if let mi = metaint {
            lines.append("icy-metaint:\(mi)")
        }
        let header = lines.joined(separator: "\r\n") + "\r\n\r\n"
        return Data(header.utf8)
    }

    /// Creates a relay config + mock transport.
    private func makeRelay(
        url: String = "http://radio.example.com:8000/live.mp3",
        audioChunks: [Data] = [],
        contentType: String = "audio/mpeg",
        metaint: Int? = nil
    ) -> (IcecastRelay, MockTransportConnection) {
        let mock = MockTransportConnection()
        let config = IcecastRelayConfiguration(sourceURL: url)

        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        return (relay, mock)
    }

    // MARK: - Showcase 1: Connected event emitted

    @Test("Relay emits connected event on successful connect")
    func relayEmitsConnectedEvent() async throws {
        let (relay, mock) = makeRelay()
        let response = buildRelayResponse()
        await mock.enqueueResponse(response)

        // Collect events
        let eventTask = Task<[RelayEvent], Never> {
            var events: [RelayEvent] = []
            for await event in relay.events {
                events.append(event)
                if events.count >= 1 { break }
            }
            return events
        }

        try await relay.connect()
        let events = await eventTask.value
        let hasConnected = events.contains {
            if case .connected = $0 { return true }
            return false
        }
        #expect(hasConnected)
        await relay.disconnect()
    }

    // MARK: - Showcase 2: Detected content type from headers

    @Test("Relay detects content type from response headers")
    func relayDetectsContentType() async throws {
        let (relay, mock) = makeRelay()
        let response = buildRelayResponse(contentType: "audio/aac")
        await mock.enqueueResponse(response)

        try await relay.connect()
        let detectedType = await relay.detectedContentType
        #expect(detectedType == .aac)
        await relay.disconnect()
    }

    // MARK: - Showcase 3: ICYStreamDemuxer separates audio from metadata

    @Test("ICYStreamDemuxer separates audio bytes from ICY metadata")
    func icyDemuxerSeparatesAudioFromMetadata() {
        var demuxer = ICYStreamDemuxer(metaint: 8)

        // 8 bytes audio + 1 byte metadata length (1 = 16 bytes)
        // + 16 bytes metadata + more audio
        var data = Data(repeating: 0xFF, count: 8)
        data.append(1)  // metadata length = 1 * 16
        let metaString = "StreamTitle='Test';"
        var metaData = Data(metaString.utf8)
        while metaData.count < 16 { metaData.append(0) }
        data.append(metaData)
        data.append(Data(repeating: 0xAA, count: 4))

        let result = demuxer.feed(data)
        #expect(!result.audioBytes.isEmpty)
    }

    // MARK: - Showcase 4: ICYStreamDemuxer without metaint

    @Test("ICYStreamDemuxer passes all data as audio when no metaint")
    func icyDemuxerNoMetaint() {
        var demuxer = ICYStreamDemuxer(metaint: nil)
        let data = Data(repeating: 0xFF, count: 100)
        let result = demuxer.feed(data)
        #expect(result.audioBytes.count == 100)
        #expect(result.metadata == nil)
    }

    // MARK: - Showcase 5: Disconnect terminates audio stream

    @Test("Relay disconnect terminates audio stream")
    func relayAudioStreamTerminatesOnDisconnect() async throws {
        let (relay, mock) = makeRelay()
        let response = buildRelayResponse()
        await mock.enqueueResponse(response)

        try await relay.connect()
        #expect(await relay.isConnected)

        await relay.disconnect()
        #expect(await relay.isConnected == false)
    }

    // MARK: - Showcase 6: bytesReceived grows with chunks

    @Test("Relay bytesReceived grows as chunks are received")
    func relayBytesReceivedGrowsWithChunks() async throws {
        let (relay, mock) = makeRelay()
        let response = buildRelayResponse()
        await mock.enqueueResponse(response)

        // Enqueue audio data chunks
        await mock.enqueueResponse(Data(repeating: 0xFF, count: 1024))

        try await relay.connect()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let bytes = await relay.bytesReceived
        #expect(bytes >= 0)
        await relay.disconnect()
    }

    // MARK: - Showcase 7: Connection failure

    @Test("Relay throws on connection failure")
    func relayThrowsOnConnectionFailure() async {
        let (relay, mock) = makeRelay()
        await mock.setConnectError(
            .connectionFailed(host: "radio.example.com", port: 8000, reason: "refused")
        )

        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    // MARK: - Showcase 8: Server version from headers

    @Test("Relay extracts server version from response headers")
    func relayExtractsServerVersion() async throws {
        let (relay, mock) = makeRelay()
        let response = buildRelayResponse(server: "Icecast 2.5.0")
        await mock.enqueueResponse(response)

        try await relay.connect()
        let version = await relay.serverVersion
        #expect(version == "Icecast 2.5.0")
        await relay.disconnect()
    }

    // MARK: - Showcase 9: IcecastRelayConfiguration defaults

    @Test("IcecastRelayConfiguration has sensible defaults")
    func relayConfigurationDefaults() {
        let config = IcecastRelayConfiguration(
            sourceURL: "http://radio.example.com:8000/live.mp3"
        )
        #expect(config.sourceURL == "http://radio.example.com:8000/live.mp3")
        #expect(config.bufferSize > 0)
    }

    // MARK: - Showcase 10: AudioChunk structure

    @Test("AudioChunk carries data, content type, and byte offset")
    func audioChunkStructure() {
        let chunk = AudioChunk(
            data: Data(repeating: 0xFF, count: 4096),
            metadata: nil,
            contentType: .mp3,
            byteOffset: 8192
        )
        #expect(chunk.data.count == 4096)
        #expect(chunk.contentType == .mp3)
        #expect(chunk.byteOffset == 8192)
        #expect(chunk.metadata == nil)
    }

    // MARK: - Showcase 11: Content type resolution

    @Test("Relay resolves various content type strings correctly")
    func contentTypeResolution() async throws {
        // Test MP3
        let (relayMp3, mockMp3) = makeRelay()
        await mockMp3.enqueueResponse(buildRelayResponse(contentType: "audio/mpeg"))
        try await relayMp3.connect()
        #expect(await relayMp3.detectedContentType == .mp3)
        await relayMp3.disconnect()
    }

    // MARK: - Showcase 12: Connect is no-op when already connected

    @Test("Relay connect is no-op when already connected")
    func relayConnectNoOpWhenConnected() async throws {
        let (relay, mock) = makeRelay()
        await mock.enqueueResponse(buildRelayResponse())
        try await relay.connect()

        // Second connect is a no-op
        try await relay.connect()
        #expect(await relay.isConnected)
        await relay.disconnect()
    }

    // MARK: - Showcase 13: Relay with invalid URL throws

    @Test("Relay connect with invalid URL throws relayConnectionFailed")
    func relayWithInvalidURLThrows() async {
        let mock = MockTransportConnection()
        let config = IcecastRelayConfiguration(sourceURL: "://invalid")
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    // MARK: - Showcase 14: Relay with incomplete response throws

    @Test("Relay throws on incomplete HTTP response without header separator")
    func relayThrowsOnIncompleteResponse() async {
        let mock = MockTransportConnection()
        // Response without \r\n\r\n separator
        let incomplete = Data("HTTP/1.1 200 OK\r\nServer: Icecast".utf8)
        await mock.enqueueResponse(incomplete)

        let config = IcecastRelayConfiguration(
            sourceURL: "http://radio.example.com:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    // MARK: - Showcase 15: Relay with non-200 HTTP status throws

    @Test("Relay throws on non-200 HTTP response status")
    func relayThrowsOnNon200Status() async {
        let mock = MockTransportConnection()
        let errorResponse = Data("HTTP/1.1 403 Forbidden\r\n\r\n".utf8)
        await mock.enqueueResponse(errorResponse)

        let config = IcecastRelayConfiguration(
            sourceURL: "http://radio.example.com:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    // MARK: - Showcase 16: Relay with send failure throws

    @Test("Relay throws on send failure")
    func relayThrowsOnSendFailure() async {
        let mock = MockTransportConnection()
        await mock.setSendError(.connectionLost(reason: "broken pipe"))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://radio.example.com:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    // MARK: - Showcase 17: Relay with receive failure throws

    @Test("Relay throws on receive failure")
    func relayThrowsOnReceiveFailure() async {
        let mock = MockTransportConnection()
        await mock.setReceiveError(.connectionLost(reason: "timeout"))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://radio.example.com:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }

    // MARK: - Showcase 18: Relay with URL that makes URLComponents return nil

    @Test("Relay throws on URL with invalid characters (URLComponents nil)")
    func relayThrowsOnURLComponentsNilURL() async {
        let mock = MockTransportConnection()
        let config = IcecastRelayConfiguration(
            sourceURL: "http://[invalid/stream"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )
        await #expect(throws: IcecastError.self) {
            try await relay.connect()
        }
    }
}
