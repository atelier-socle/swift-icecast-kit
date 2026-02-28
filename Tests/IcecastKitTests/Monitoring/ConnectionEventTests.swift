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

    // MARK: - ConnectionEvent Sendable

    @Test("ConnectionEvent is Sendable (compile-time check)")
    func connectionEventSendable() {
        let event: any Sendable = ConnectionEvent.error(.notConnected)
        #expect(event is ConnectionEvent)
    }
}
