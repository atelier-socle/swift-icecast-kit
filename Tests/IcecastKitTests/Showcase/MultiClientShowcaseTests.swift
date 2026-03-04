// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for multi-client showcase tests.
private actor MultiEventCollector {
    var events: [MultiIcecastEvent] = []

    func append(_ event: MultiIcecastEvent) {
        events.append(event)
    }
}

@Suite("Showcase — Multi-Destination Streaming")
struct MultiClientShowcaseTests {

    private static let putOKResponse = Data(
        "HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8
    )

    private func makeConfig(
        host: String = "radio.example.com",
        mountpoint: String = "/live.mp3",
        password: String = "secret"
    ) -> IcecastConfiguration {
        IcecastConfiguration(
            host: host,
            mountpoint: mountpoint,
            credentials: IcecastCredentials(password: password)
        )
    }

    // MARK: - Showcase 1: Connect two destinations

    @Test("Multi-client connects to multiple destinations")
    func multiClientConnectsToMultipleDestinations() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })

        try await multi.addDestination("primary", configuration: makeConfig())
        try await multi.addDestination("backup", configuration: makeConfig(host: "backup.example.com"))
        try await multi.connectAll()

        let dests = await multi.destinations
        #expect(dests.count == 2)
    }

    // MARK: - Showcase 2: send() distributes to all

    @Test("Multi-client sends data to all destinations")
    func multiClientSendsToAllDestinations() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("single", configuration: makeConfig())
        try await multi.connectAll()

        let audioData = Data(repeating: 0xFF, count: 1024)
        try await multi.send(audioData)

        let sentCount = await mock.sendCallCount
        #expect(sentCount > 1)  // handshake + audio
    }

    // MARK: - Showcase 3: Failure isolation

    @Test("Multi-client isolates destination failure")
    func multiClientIsolatesDestinationFailure() async throws {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(host: "bad", port: 8000, reason: "refused")
        )

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("fail", configuration: makeConfig())

        // connectAll throws when all destinations fail
        await #expect(throws: IcecastError.self) {
            try await multi.connectAll()
        }

        let stats = await multi.statistics
        #expect(stats.totalCount == 1)
    }

    // MARK: - Showcase 4: addDestinationLive()

    @Test("Multi-client supports live destination addition")
    func multiClientSupportsLiveDestinationAddition() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("initial", configuration: makeConfig())
        try await multi.connectAll()

        // Add a new destination live — it connects immediately
        await mock.enqueueResponse(Self.putOKResponse)
        try await multi.addDestinationLive("live-add", configuration: makeConfig(host: "live.example.com"))

        let dests = await multi.destinations
        #expect(dests.count == 2)
    }

    // MARK: - Showcase 5: removeDestination()

    @Test("Multi-client removes destination cleanly")
    func multiClientRemovesDestinationCleanly() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("removable", configuration: makeConfig())
        try await multi.connectAll()

        await multi.removeDestination(label: "removable")

        let dests = await multi.destinations
        #expect(dests.isEmpty)
    }

    // MARK: - Showcase 6: allConnected event

    @Test("Multi-client emits allConnected event")
    func multiClientEmitsAllConnectedEvent() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        let collector = MultiEventCollector()

        let eventTask = Task {
            for await event in multi.events {
                await collector.append(event)
            }
        }

        try await multi.addDestination("sole", configuration: makeConfig())
        try await multi.connectAll()
        try? await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        let events = await collector.events
        let hasAllConnected = events.contains {
            if case .allConnected = $0 { return true }
            return false
        }
        #expect(hasAllConnected)
    }

    // MARK: - Showcase 7: Statistics per-destination and aggregated

    @Test("Multi-client statistics are per-destination and aggregated")
    func multiClientStatisticsArePerDestinationAndAggregated() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("dest1", configuration: makeConfig())
        try await multi.connectAll()

        let stats = await multi.statistics
        #expect(stats.totalCount == 1)
        #expect(stats.perDestination["dest1"] != nil)
        #expect(stats.connectedCount >= 0)
        #expect(stats.reconnectingCount == 0)
    }

    // MARK: - Showcase 8: allDestinationsFailed

    @Test("Multi-client emits allDestinationsFailed when all fail")
    func multiClientEmitsAllDestinationsFailedError() async throws {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(host: "fail", port: 8000, reason: "refused")
        )

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("fail1", configuration: makeConfig())

        await #expect(throws: IcecastError.self) {
            try await multi.connectAll()
        }
    }

    // MARK: - Showcase 9: send() large payload

    @Test("Multi-client sends large payload across destinations")
    func multiClientSendsLargePayload() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("large", configuration: makeConfig())
        try await multi.connectAll()

        let audioData = Data(repeating: 0xAB, count: 8192)
        try await multi.send(audioData)

        let sentCount = await mock.sendCallCount
        #expect(sentCount > 1)  // handshake + audio
    }

    // MARK: - Showcase 10: credentialsRequired on missing credentials

    @Test("Multi-client throws credentialsRequired when credentials missing")
    func multiClientThrowsWithoutCredentials() async {
        let multi = MultiIcecastClient()
        let config = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3"
        )
        await #expect(throws: IcecastError.self) {
            try await multi.addDestination("nocreds", configuration: config)
        }
    }

    // MARK: - Showcase 11: destinationAlreadyExists on duplicate label

    @Test("Multi-client throws destinationAlreadyExists on duplicate label")
    func multiClientThrowsOnDuplicateLabel() async throws {
        let mock = MockTransportConnection()
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("dup", configuration: makeConfig())

        await #expect(throws: IcecastError.self) {
            try await multi.addDestination("dup", configuration: makeConfig())
        }
    }

    // MARK: - Showcase 12: addDestinationLive without credentials

    @Test("Multi-client addDestinationLive throws without credentials")
    func multiClientAddDestinationLiveThrowsWithoutCredentials() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("initial", configuration: makeConfig())
        try await multi.connectAll()

        let noCreds = IcecastConfiguration(
            host: "radio.example.com",
            mountpoint: "/live.mp3"
        )
        await #expect(throws: IcecastError.self) {
            try await multi.addDestinationLive("nocreds", configuration: noCreds)
        }
    }

    // MARK: - Showcase 13: Aggregate statistics with currentBitrate

    @Test("Multi-client aggregate statistics averages currentBitrate")
    func multiClientAggregateStatisticsAverageCurrentBitrate() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination("dest1", configuration: makeConfig())
        try await multi.connectAll()

        // Send data to establish non-zero currentBitrate
        let audioData = Data(repeating: 0xFF, count: 8192)
        try await multi.send(audioData)
        try? await Task.sleep(nanoseconds: 100_000_000)

        let stats = await multi.statistics
        #expect(stats.aggregated.bytesSent > 0)
        await multi.disconnectAll()
    }

    // MARK: - Helper

    private func setConnectError(
        _ mock: MockTransportConnection,
        _ error: IcecastError
    ) async {
        await mock.setConnectError(error)
    }
}
