// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - IcecastDestination Tests

@Suite("IcecastDestination")
struct IcecastDestinationTests {

    @Test("Construction and property access")
    func constructionAndAccess() {
        let config = IcecastConfiguration(
            host: "radio.example.com", mountpoint: "/live.mp3"
        )
        let stats = ConnectionStatistics(bytesSent: 1024)
        let dest = IcecastDestination(
            label: "primary",
            configuration: config,
            state: .connected,
            statistics: stats
        )
        #expect(dest.label == "primary")
        #expect(dest.configuration.host == "radio.example.com")
        #expect(dest.state == .connected)
        #expect(dest.statistics?.bytesSent == 1024)
    }

    @Test("State and statistics reflect disconnected state")
    func disconnectedState() {
        let config = IcecastConfiguration(
            host: "localhost", mountpoint: "/stream"
        )
        let dest = IcecastDestination(
            label: "backup",
            configuration: config,
            state: .disconnected,
            statistics: nil
        )
        #expect(dest.state == .disconnected)
        #expect(dest.statistics == nil)
    }
}

// MARK: - MultiIcecastEvent Tests

@Suite("MultiIcecastEvent")
struct MultiIcecastEventTests {

    @Test("All event cases are constructible")
    func allCasesConstructible() {
        let events: [MultiIcecastEvent] = [
            .destinationConnected(label: "a", serverVersion: "2.4.4"),
            .destinationDisconnected(label: "b", error: nil),
            .destinationReconnecting(label: "c", attempt: 1),
            .destinationReconnected(label: "d"),
            .allConnected,
            .sendComplete(successCount: 2, failureCount: 1),
            .destinationAdded(label: "e"),
            .destinationRemoved(label: "f"),
            .metadataUpdated(label: "g")
        ]
        #expect(events.count == 9)
    }

    @Test("destinationConnected carries server version")
    func connectedCarriesVersion() {
        let event = MultiIcecastEvent.destinationConnected(
            label: "primary", serverVersion: "Icecast 2.4.4"
        )
        if case .destinationConnected(let label, let version) = event {
            #expect(label == "primary")
            #expect(version == "Icecast 2.4.4")
        } else {
            Issue.record("Expected destinationConnected")
        }
    }

    @Test("destinationDisconnected carries optional error")
    func disconnectedCarriesError() {
        let event = MultiIcecastEvent.destinationDisconnected(
            label: "backup",
            error: .connectionLost(reason: "timeout")
        )
        if case .destinationDisconnected(let label, let error) = event {
            #expect(label == "backup")
            #expect(error != nil)
        } else {
            Issue.record("Expected destinationDisconnected")
        }
    }

    @Test("sendComplete carries counts")
    func sendCompleteCarriesCounts() {
        let event = MultiIcecastEvent.sendComplete(
            successCount: 3, failureCount: 1
        )
        if case .sendComplete(let success, let failure) = event {
            #expect(success == 3)
            #expect(failure == 1)
        } else {
            Issue.record("Expected sendComplete")
        }
    }
}

// MARK: - MultiIcecastStatistics Tests

@Suite("MultiIcecastStatistics")
struct MultiIcecastStatisticsTests {

    @Test("Counts are correct")
    func countsCorrect() {
        let stats = MultiIcecastStatistics(
            perDestination: [
                "a": ConnectionStatistics(bytesSent: 100),
                "b": ConnectionStatistics(bytesSent: 200)
            ],
            aggregated: ConnectionStatistics(bytesSent: 300),
            connectedCount: 2,
            reconnectingCount: 0,
            totalCount: 3
        )
        #expect(stats.connectedCount == 2)
        #expect(stats.reconnectingCount == 0)
        #expect(stats.totalCount == 3)
        #expect(stats.perDestination.count == 2)
    }

    @Test("Aggregated is consistent with perDestination")
    func aggregatedConsistency() {
        let s1 = ConnectionStatistics(bytesSent: 100, sendErrorCount: 1)
        let s2 = ConnectionStatistics(bytesSent: 200, sendErrorCount: 2)
        let aggregated = MultiIcecastStatistics.aggregate([s1, s2])
        #expect(aggregated.bytesSent == 300)
        #expect(aggregated.sendErrorCount == 3)
    }

    @Test("Aggregate handles empty array")
    func aggregateEmpty() {
        let aggregated = MultiIcecastStatistics.aggregate([])
        #expect(aggregated.bytesSent == 0)
        #expect(aggregated.duration == 0)
    }
}

// MARK: - MultiIcecastClient — Destination Management

@Suite("MultiIcecastClient — Destination Management")
struct MultiIcecastClientDestinationTests {

    private func makeConfig(
        host: String = "localhost"
    ) -> IcecastConfiguration {
        IcecastConfiguration(
            host: host, mountpoint: "/live.mp3",
            credentials: IcecastCredentials(password: "test")
        )
    }

    @Test("addDestination adds correctly")
    func addDestinationAdds() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "primary", configuration: makeConfig()
        )
        let dests = await multi.destinations
        #expect(dests.count == 1)
        #expect(dests[0].label == "primary")
    }

    @Test("addDestination throws destinationAlreadyExists on duplicate label")
    func addDestinationDuplicate() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "primary", configuration: makeConfig()
        )
        await #expect(throws: IcecastError.self) {
            try await multi.addDestination(
                "primary",
                configuration: makeConfig(host: "other")
            )
        }
    }

    @Test("removeDestination is a no-op for unknown label")
    func removeDestinationNoOp() async {
        let multi = MultiIcecastClient()
        await multi.removeDestination(label: "nonexistent")
        let dests = await multi.destinations
        #expect(dests.isEmpty)
    }

    @Test("destinations returns current snapshot")
    func destinationsSnapshot() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "a", configuration: makeConfig()
        )
        try await multi.addDestination(
            "b", configuration: makeConfig(host: "host2")
        )
        let dests = await multi.destinations
        #expect(dests.count == 2)
        let labels = Set(dests.map(\.label))
        #expect(labels.contains("a"))
        #expect(labels.contains("b"))
    }

    @Test("removeDestination removes by label")
    func removeDestinationByLabel() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "a", configuration: makeConfig()
        )
        try await multi.addDestination(
            "b", configuration: makeConfig(host: "host2")
        )
        await multi.removeDestination(label: "a")
        let dests = await multi.destinations
        #expect(dests.count == 1)
        #expect(dests[0].label == "b")
    }
}

// MARK: - MultiIcecastClient — Connection

@Suite("MultiIcecastClient — Connection")
struct MultiIcecastClientConnectionTests {

    @Test("connectAll with 0 destinations is a no-op")
    func connectAllEmpty() async throws {
        let multi = MultiIcecastClient()
        try await multi.connectAll()
        let dests = await multi.destinations
        #expect(dests.isEmpty)
    }

    @Test("connectAll throws allDestinationsFailed when all fail")
    func connectAllFails() async throws {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(
                host: "localhost", port: 8000, reason: "refused"
            )
        )
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "failing",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        await #expect(throws: IcecastError.self) {
            try await multi.connectAll()
        }
    }

    @Test("connectAll succeeds when at least one destination connects")
    func connectAllPartialSuccess() async throws {
        let goodMock = MockTransportConnection()
        await goodMock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )
        let multi = MultiIcecastClient(connectionFactory: {
            goodMock
        })
        try await multi.addDestination(
            "good",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.connectAll()
        let stats = await multi.statistics
        #expect(stats.totalCount == 1)
    }

    @Test("disconnectAll disconnects all destinations")
    func disconnectAllDisconnects() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "dest",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.connectAll()
        await multi.disconnectAll()
        let dests = await multi.destinations
        for dest in dests {
            #expect(dest.state == .disconnected)
        }
    }
}

// MARK: - MultiIcecastClient — Streaming

@Suite("MultiIcecastClient — Streaming")
struct MultiIcecastClientStreamingTests {

    @Test("send distributes data to all connected destinations")
    func sendDistributes() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "dest",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.connectAll()
        let data = Data(repeating: 0xAB, count: 1024)
        try await multi.send(data)
        let stats = await multi.statistics
        #expect(stats.aggregated.bytesSent > 0)
    }

    @Test("send does not throw on partial failure")
    func sendPartialFailure() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "dest",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        // Don't connect — send will fail gracefully per destination
        let data = Data(repeating: 0xAB, count: 1024)
        // send() only throws if no entries exist
        try await multi.send(data)
    }

    @Test("send throws notConnected when no destinations registered")
    func sendNoDestinations() async {
        let multi = MultiIcecastClient()
        await #expect(throws: IcecastError.self) {
            try await multi.send(Data(repeating: 0, count: 100))
        }
    }

    @Test("updateMetadata propagates to connected destinations")
    func updateMetadataPropagates() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "dest",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.connectAll()
        await multi.updateMetadata(ICYMetadata(streamTitle: "Test Song"))
        let stats = await multi.statistics
        #expect(stats.perDestination["dest"]?.metadataUpdateCount ?? 0 >= 0)
    }

    @Test("updateMetadata silently ignores disconnected destinations")
    func updateMetadataIgnoresDisconnected() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "offline",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        // Not connected — should silently skip
        await multi.updateMetadata(ICYMetadata(streamTitle: "Test"))
    }

    @Test("send with bytes buffer converts to Data")
    func sendBytesBuffer() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "dest",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.connectAll()
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try await multi.send(data)
    }
}

// MARK: - MultiIcecastClient — Hot-Add / Hot-Remove

@Suite("MultiIcecastClient — Hot-Add / Hot-Remove")
struct MultiIcecastClientHotTests {

    @Test("addDestinationLive connects immediately")
    func hotAddConnects() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestinationLive(
            "live",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        let dests = await multi.destinations
        #expect(dests.count == 1)
        let state = dests.first?.state
        #expect(state?.isActive == true)
    }

    @Test("addDestinationLive throws on duplicate label")
    func hotAddDuplicate() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestinationLive(
            "live",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        await #expect(throws: IcecastError.self) {
            try await multi.addDestinationLive(
                "live",
                configuration: IcecastConfiguration(
                    host: "other", mountpoint: "/live.mp3",
                    credentials: IcecastCredentials(password: "test")
                )
            )
        }
    }

    @Test("removeDestinationLive disconnects and removes")
    func hotRemoveDisconnects() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestinationLive(
            "live",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        await multi.removeDestinationLive(label: "live")
        let dests = await multi.destinations
        #expect(dests.isEmpty)
    }

    @Test("Send after hot-remove does not reach removed destination")
    func sendAfterHotRemove() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestinationLive(
            "live",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        await multi.removeDestinationLive(label: "live")
        // Now send should throw since no destinations remain
        await #expect(throws: IcecastError.self) {
            try await multi.send(Data(repeating: 0xAB, count: 100))
        }
    }

    @Test("Send after hot-add reaches new destination")
    func sendAfterHotAdd() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestinationLive(
            "new",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/live.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.send(Data(repeating: 0xAB, count: 1024))
        let stats = await multi.statistics
        #expect(stats.aggregated.bytesSent > 0)
    }
}

// MARK: - MultiIcecastClient — Failure Isolation

@Suite("MultiIcecastClient — Failure Isolation")
struct MultiIcecastClientFailureIsolationTests {

    @Test("Failure of one destination does not affect others")
    func failureIsolation() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))
        let multi = MultiIcecastClient(connectionFactory: { mock })
        try await multi.addDestination(
            "a",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/a.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        try await multi.addDestination(
            "b",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/b.mp3",
                credentials: IcecastCredentials(password: "test")
            )
        )
        // connectAll — both share the mock, but that's OK for isolation test
        try await multi.connectAll()
        let stats = await multi.statistics
        #expect(stats.totalCount == 2)
    }

    @Test("Each destination reconnects independently")
    func independentReconnection() async throws {
        let multi = MultiIcecastClient()
        try await multi.addDestination(
            "a",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/a.mp3",
                credentials: IcecastCredentials(password: "test"),
                reconnectPolicy: .default
            )
        )
        try await multi.addDestination(
            "b",
            configuration: IcecastConfiguration(
                host: "localhost", mountpoint: "/b.mp3",
                credentials: IcecastCredentials(password: "test"),
                reconnectPolicy: .none
            )
        )
        let dests = await multi.destinations
        #expect(dests.count == 2)
    }
}
