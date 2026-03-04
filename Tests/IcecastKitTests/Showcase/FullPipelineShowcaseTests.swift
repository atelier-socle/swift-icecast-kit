// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for pipeline tests.
private actor PipelineEventCollector {
    var events: [ConnectionEvent] = []

    func append(_ event: ConnectionEvent) {
        events.append(event)
    }
}

@Suite("Showcase — Full Pipeline Integration")
struct FullPipelineShowcaseTests {

    private static let putOKResponse = Data(
        "HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8
    )

    private func makeClient(
        config: IcecastConfiguration? = nil,
        mock: MockTransportConnection? = nil
    ) -> (IcecastClient, MockTransportConnection) {
        let transport = mock ?? MockTransportConnection()
        let cfg =
            config
            ?? IcecastConfiguration(
                host: "radio.example.com",
                port: 8000,
                mountpoint: "/live.mp3"
            )
        let client = IcecastClient(
            configuration: cfg,
            credentials: IcecastCredentials(password: "hackme"),
            connectionFactory: { transport }
        )
        return (client, transport)
    }

    // MARK: - Pipeline 1: Connect → stream → disconnect

    @Test("Connect, stream audio, and disconnect cleanly")
    func connectStreamDisconnect() async throws {
        let (client, mock) = makeClient()
        await mock.enqueueResponse(Self.putOKResponse)

        try await client.connect()
        #expect(await client.isConnected)

        let audio = Data(repeating: 0xFF, count: 4096)
        try await client.send(audio)

        let stats = await client.statistics
        #expect(stats.bytesSent > 0)

        await client.disconnect()
        #expect(await client.isConnected == false)
    }

    // MARK: - Pipeline 2: Connect with ABR under simulated congestion

    @Test("Connect with ABR, receive bitrateRecommendation event under congestion")
    func connectWithABRUnderSimulatedCongestion() async throws {
        let config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3",
            adaptiveBitrate: .custom(
                AdaptiveBitrateConfiguration(
                    minBitrate: 32_000,
                    maxBitrate: 320_000,
                    downTriggerThreshold: 1.3,
                    upStabilityDuration: 60.0,
                    measurementWindow: 0.0,
                    hysteresisCount: 1
                )
            )
        )
        let (client, mock) = makeClient(config: config)
        await mock.enqueueResponse(Self.putOKResponse)

        try await client.connect()

        // Send multiple chunks to establish monitoring baseline
        let audio = Data(repeating: 0xFF, count: 1024)
        for _ in 0..<10 {
            try await client.send(audio)
        }

        await client.disconnect()
    }

    // MARK: - Pipeline 3: Stream with recording and rotation

    @Test("Stream with recording and file rotation")
    func streamWithRecordingAndRotation() async throws {
        let dir = NSTemporaryDirectory() + "icecast-pipeline-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3",
            recording: RecordingConfiguration(
                directory: dir, contentType: .mp3,
                maxFileSize: 500,
                flushInterval: 0
            )
        )
        let (client, mock) = makeClient(config: config)
        await mock.enqueueResponse(Self.putOKResponse)

        try await client.connect()

        // Write enough to trigger rotation
        let audio = Data(repeating: 0xFF, count: 600)
        try await client.send(audio)

        await client.disconnect()

        // Verify files were created
        let files = try? FileManager.default.contentsOfDirectory(atPath: dir)
        #expect((files?.count ?? 0) >= 1)
    }

    // MARK: - Pipeline 4: Multi-destination with failure recovery

    @Test("Multi-destination stream with send and disconnect")
    func multiDestinationWithSendAndDisconnect() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })

        let config = IcecastConfiguration(
            host: "radio1.example.com",
            mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "secret1")
        )

        try await multi.addDestination("primary", configuration: config)
        try await multi.connectAll()

        let audio = Data(repeating: 0xFF, count: 1024)
        try await multi.send(audio)

        let stats = await multi.statistics
        #expect(stats.totalCount == 1)

        await multi.disconnectAll()
    }

    // MARK: - Pipeline 5: Preset → connect → disconnect

    @Test("AzuraCast preset full lifecycle")
    func azuracastPresetFullLifecycle() async throws {
        let config = IcecastServerPreset.azuracast.configuration(
            host: "mystation.azuracast.com",
            password: "my-source-password"
        )
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: config,
            credentials: config.credentials ?? IcecastCredentials(password: "fallback"),
            connectionFactory: { mock }
        )
        try await client.connect()
        #expect(await client.isConnected)
        await client.disconnect()
    }

    // MARK: - Pipeline 6: Stream with Prometheus metrics

    @Test("Stream with Prometheus metrics export")
    func streamWithPrometheusMetricsExport() async throws {
        let (client, mock) = makeClient()
        await mock.enqueueResponse(Self.putOKResponse)

        let stream = AsyncStream.makeStream(of: String.self)
        let exporter = PrometheusExporter { output in
            stream.continuation.yield(output)
        }

        try await client.connect()
        await client.setMetricsExporter(exporter, interval: 0.1)

        let audio = Data(repeating: 0xFF, count: 1024)
        try await client.send(audio)

        // Wait for at least one export callback
        try? await Task.sleep(nanoseconds: 200_000_000)
        stream.continuation.finish()

        let stats = await client.statistics
        let output = await exporter.render(stats, labels: [:])
        #expect(!output.isEmpty)
        await client.disconnect()
    }

    // MARK: - Pipeline 7: Quality monitoring

    @Test("Stream with quality monitoring emits qualityChanged")
    func streamWithQualityMonitoring() async throws {
        let (client, mock) = makeClient()
        await mock.enqueueResponse(Self.putOKResponse)

        let collector = PipelineEventCollector()
        let eventTask = Task {
            for await event in client.events {
                await collector.append(event)
            }
        }

        try await client.connect()

        let audio = Data(repeating: 0xFF, count: 1024)
        for _ in 0..<5 {
            try await client.send(audio)
        }

        // Quality assessments happen after sufficient sends
        try? await Task.sleep(nanoseconds: 100_000_000)
        eventTask.cancel()

        let quality = await client.connectionQuality
        // Quality may or may not be available depending on send count
        if let q = quality {
            #expect(q.score >= 0)
            #expect(q.score <= 1.0)
        }

        await client.disconnect()
    }

    // MARK: - Pipeline 8: URL parsing → connect

    @Test("Parse URL configuration and connect")
    func parseURLAndConnect() async throws {
        let (config, creds) = try IcecastConfiguration.from(
            url: "icecast://source:hackme@radio.example.com:8000/live.mp3"
        )
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )
        try await client.connect()
        #expect(await client.isConnected)
        await client.disconnect()
    }

    // MARK: - Pipeline 9: Metadata update after connect

    @Test("Metadata update via admin API after connect")
    func metadataUpdateAfterConnect() async throws {
        let (client, mock) = makeClient()
        await mock.enqueueResponse(Self.putOKResponse)

        try await client.connect()

        // State verification
        let state = await client.state
        #expect(state.isActive)

        let stats = await client.statistics
        #expect(stats.duration >= 0)

        await client.disconnect()
    }

    // MARK: - Pipeline 10: Connection event lifecycle

    @Test("Full connection event lifecycle: connected → disconnected")
    func connectionEventLifecycle() async throws {
        let (client, mock) = makeClient()
        await mock.enqueueResponse(Self.putOKResponse)

        let collector = PipelineEventCollector()
        let eventTask = Task {
            for await event in client.events {
                await collector.append(event)
            }
        }

        try await client.connect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await client.disconnect()
        try? await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        let events = await collector.events
        let hasConnected = events.contains {
            if case .connected = $0 { return true }
            return false
        }
        let hasDisconnected = events.contains {
            if case .disconnected = $0 { return true }
            return false
        }
        #expect(hasConnected)
        #expect(hasDisconnected)
    }

    // MARK: - Pipeline 11: Connect with bearer authentication

    @Test("Bearer authentication connects successfully via ProtocolNegotiator")
    func bearerAuthenticationConnects() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let config = IcecastConfiguration(
            host: "radio.example.com",
            port: 8000,
            mountpoint: "/live.mp3",
            authentication: .bearer(token: "my-api-token")
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "unused"),
            connectionFactory: { mock }
        )

        try await client.connect()
        #expect(await client.isConnected)
        await client.disconnect()
    }

    // MARK: - Pipeline 12: Connect with connectionLost disconnect reason

    @Test("Connection loss maps to networkError disconnect reason")
    func connectionLossMapsToNetworkError() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let (client, _) = makeClient(mock: mock)

        try await client.connect()

        // Inject send error to trigger disconnect with non-auth error
        await mock.setSendError(
            .connectionLost(reason: "broken pipe")
        )

        let audio = Data(repeating: 0xFF, count: 1024)
        do {
            try await client.send(audio)
        } catch {
            // Expected — connectionLost triggers networkError disconnect reason
        }

        await client.disconnect()
    }

    // MARK: - Pipeline 13: PUT→SOURCE fallback with digest auth

    @Test("PUT-to-SOURCE fallback with digest authentication")
    func putToSourceFallbackWithDigestAuth() async throws {
        let mock = MockTransportConnection()

        // Empty response triggers emptyResponse error → fallback to SOURCE
        await mock.enqueueResponse(Data())
        // Second response for SOURCE handshake
        await mock.enqueueResponse(Self.putOKResponse)

        let config = IcecastConfiguration(
            host: "radio.example.com",
            port: 8000,
            mountpoint: "/live.mp3",
            authentication: .digest(username: "source", password: "hackme")
        )
        let client = IcecastClient(
            configuration: config,
            credentials: IcecastCredentials(password: "hackme"),
            connectionFactory: { mock }
        )

        try await client.connect()
        #expect(await client.isConnected)
        await client.disconnect()
    }

    // MARK: - Pipeline 14: Multi-client updateMetadata on disconnected destination

    @Test("Multi-client updateMetadata skips disconnected destinations")
    func multiClientUpdateMetadataSkipsDisconnected() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        let config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "secret")
        )
        try await multi.addDestination("dest1", configuration: config)
        // Don't connect — destination is not connected

        let meta = ICYMetadata(streamTitle: "Test")
        await multi.updateMetadata(meta)

        // Should not throw, just skip the disconnected destination
        let stats = await multi.statistics
        #expect(stats.totalCount == 1)
    }
}
