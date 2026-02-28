// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ConnectionEvent and Monitoring Types")
struct ConnectionEventTests {

    // MARK: - DisconnectReason

    @Test("All DisconnectReason cases have non-empty description")
    func disconnectReasonDescriptions() {
        let reasons: [DisconnectReason] = [
            .requested,
            .serverClosed,
            .networkError("timeout"),
            .authenticationFailed,
            .mountpointInUse,
            .maxRetriesExceeded,
            .contentTypeRejected
        ]
        for reason in reasons {
            #expect(!reason.description.isEmpty)
        }
    }

    @Test("DisconnectReason Hashable with same values are equal")
    func disconnectReasonHashable() {
        let a = DisconnectReason.requested
        let b = DisconnectReason.requested
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("DisconnectReason Hashable with different values are not equal")
    func disconnectReasonHashableNotEqual() {
        let a = DisconnectReason.requested
        let b = DisconnectReason.serverClosed
        #expect(a != b)
    }

    @Test("DisconnectReason networkError with different messages are not equal")
    func disconnectReasonNetworkErrorDifferent() {
        let a = DisconnectReason.networkError("timeout")
        let b = DisconnectReason.networkError("refused")
        #expect(a != b)
    }

    // MARK: - MetadataUpdateMethod

    @Test("MetadataUpdateMethod values are hashable")
    func metadataUpdateMethodHashable() {
        let a = MetadataUpdateMethod.adminAPI
        let b = MetadataUpdateMethod.adminAPI
        let c = MetadataUpdateMethod.inline
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - ConnectionStatistics

    @Test("ConnectionStatistics init with defaults produces all zeros")
    func statisticsDefaults() {
        let stats = ConnectionStatistics()
        #expect(stats.bytesSent == 0)
        #expect(stats.bytesTotal == 0)
        #expect(stats.duration == 0)
        #expect(stats.averageBitrate == 0)
        #expect(stats.currentBitrate == 0)
        #expect(stats.metadataUpdateCount == 0)
        #expect(stats.reconnectionCount == 0)
        #expect(stats.connectedSince == nil)
        #expect(stats.sendErrorCount == 0)
    }

    @Test("ConnectionStatistics is Hashable")
    func statisticsHashable() {
        let a = ConnectionStatistics(bytesSent: 100, bytesTotal: 200)
        let b = ConnectionStatistics(bytesSent: 100, bytesTotal: 200)
        let c = ConnectionStatistics(bytesSent: 300)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a != c)
    }

    // MARK: - ConnectionStatistics Enhanced

    @Test("ConnectionStatistics with populated values")
    func statisticsPopulatedValues() {
        let date = Date()
        let stats = ConnectionStatistics(
            bytesSent: 5000,
            bytesTotal: 6000,
            duration: 10.0,
            averageBitrate: 4800.0,
            currentBitrate: 4000.0,
            metadataUpdateCount: 3,
            reconnectionCount: 1,
            connectedSince: date,
            sendErrorCount: 2
        )
        #expect(stats.bytesSent == 5000)
        #expect(stats.bytesTotal == 6000)
        #expect(stats.duration == 10.0)
        #expect(stats.averageBitrate == 4800.0)
        #expect(stats.currentBitrate == 4000.0)
        #expect(stats.metadataUpdateCount == 3)
        #expect(stats.reconnectionCount == 1)
        #expect(stats.connectedSince == date)
        #expect(stats.sendErrorCount == 2)
    }

    @Test("ConnectionStatistics averageBitrate manual calculation")
    func statisticsAverageBitrateManualCalc() {
        let bytes: UInt64 = 10000
        let duration: TimeInterval = 8.0
        let expected = Double(bytes) * 8.0 / duration
        let stats = ConnectionStatistics(
            bytesSent: bytes,
            bytesTotal: bytes,
            duration: duration,
            averageBitrate: expected
        )
        #expect(stats.averageBitrate == expected)
    }

    @Test("ConnectionStatistics duration correctness")
    func statisticsDurationCorrectness() {
        let stats = ConnectionStatistics(duration: 42.5)
        #expect(stats.duration == 42.5)
    }

    @Test("ConnectionStatistics same stats are equal")
    func statisticsSameAreEqual() {
        let date = Date()
        let a = ConnectionStatistics(
            bytesSent: 100,
            bytesTotal: 200,
            duration: 5.0,
            averageBitrate: 320.0,
            currentBitrate: 256.0,
            metadataUpdateCount: 1,
            reconnectionCount: 0,
            connectedSince: date,
            sendErrorCount: 0
        )
        let b = ConnectionStatistics(
            bytesSent: 100,
            bytesTotal: 200,
            duration: 5.0,
            averageBitrate: 320.0,
            currentBitrate: 256.0,
            metadataUpdateCount: 1,
            reconnectionCount: 0,
            connectedSince: date,
            sendErrorCount: 0
        )
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("ConnectionStatistics different stats are not equal")
    func statisticsDifferentAreNotEqual() {
        let a = ConnectionStatistics(bytesSent: 100, sendErrorCount: 0)
        let b = ConnectionStatistics(bytesSent: 100, sendErrorCount: 1)
        #expect(a != b)
    }

    @Test("ConnectionStatistics all fields accessible and settable")
    func statisticsFieldsAccessibleAndSettable() {
        var stats = ConnectionStatistics()
        stats.bytesSent = 42
        stats.bytesTotal = 50
        stats.duration = 1.5
        stats.averageBitrate = 224.0
        stats.currentBitrate = 128.0
        stats.metadataUpdateCount = 7
        stats.reconnectionCount = 3
        stats.connectedSince = Date()
        stats.sendErrorCount = 4
        #expect(stats.bytesSent == 42)
        #expect(stats.bytesTotal == 50)
        #expect(stats.duration == 1.5)
        #expect(stats.averageBitrate == 224.0)
        #expect(stats.currentBitrate == 128.0)
        #expect(stats.metadataUpdateCount == 7)
        #expect(stats.reconnectionCount == 3)
        #expect(stats.connectedSince != nil)
        #expect(stats.sendErrorCount == 4)
    }

    // MARK: - ConnectionEvent Sendable

    @Test("ConnectionEvent is Sendable (compile-time check)")
    func connectionEventSendable() {
        let event: any Sendable = ConnectionEvent.error(.notConnected)
        #expect(event is ConnectionEvent)
    }

    @Test("ConnectionEvent statistics case carries data")
    func connectionEventStatisticsCase() {
        let stats = ConnectionStatistics(bytesSent: 500, bytesTotal: 600)
        let event = ConnectionEvent.statistics(stats)
        if case .statistics(let contained) = event {
            #expect(contained.bytesSent == 500)
            #expect(contained.bytesTotal == 600)
        } else {
            Issue.record("Expected statistics event")
        }
    }

    @Test("ConnectionEvent connected case carries connection info")
    func connectionEventConnectedCase() {
        let event = ConnectionEvent.connected(
            host: "example.com",
            port: 8000,
            mountpoint: "/live",
            protocolName: "Icecast PUT"
        )
        if case .connected(let host, let port, let mountpoint, let proto) = event {
            #expect(host == "example.com")
            #expect(port == 8000)
            #expect(mountpoint == "/live")
            #expect(proto == "Icecast PUT")
        } else {
            Issue.record("Expected connected event")
        }
    }
}
