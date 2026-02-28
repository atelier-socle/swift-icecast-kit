// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Testing

@testable import IcecastKit

@Suite("ConnectionState")
struct ConnectionStateTests {

    // MARK: - canSend

    @Test("canSend is true for connected state")
    func canSendConnected() {
        let state = ConnectionState.connected
        #expect(state.canSend)
    }

    @Test("canSend is true for streaming state")
    func canSendStreaming() {
        let state = ConnectionState.streaming
        #expect(state.canSend)
    }

    @Test("canSend is false for disconnected state")
    func canSendDisconnected() {
        let state = ConnectionState.disconnected
        #expect(!state.canSend)
    }

    @Test("canSend is false for connecting state")
    func canSendConnecting() {
        let state = ConnectionState.connecting
        #expect(!state.canSend)
    }

    @Test("canSend is false for authenticating state")
    func canSendAuthenticating() {
        let state = ConnectionState.authenticating
        #expect(!state.canSend)
    }

    @Test("canSend is false for reconnecting state")
    func canSendReconnecting() {
        let state = ConnectionState.reconnecting(attempt: 0, nextRetryIn: 1.0)
        #expect(!state.canSend)
    }

    @Test("canSend is false for failed state")
    func canSendFailed() {
        let state = ConnectionState.failed(.notConnected)
        #expect(!state.canSend)
    }

    // MARK: - isActive

    @Test("isActive is true for connected and streaming only")
    func isActiveStates() {
        #expect(ConnectionState.connected.isActive)
        #expect(ConnectionState.streaming.isActive)
        #expect(!ConnectionState.disconnected.isActive)
        #expect(!ConnectionState.connecting.isActive)
        #expect(!ConnectionState.authenticating.isActive)
        #expect(!ConnectionState.reconnecting(attempt: 0, nextRetryIn: 1.0).isActive)
        #expect(!ConnectionState.failed(.notConnected).isActive)
    }

    // MARK: - CustomStringConvertible

    @Test("All states have non-empty description")
    func allDescriptionsNonEmpty() {
        let states: [ConnectionState] = [
            .disconnected,
            .connecting,
            .authenticating,
            .connected,
            .streaming,
            .reconnecting(attempt: 2, nextRetryIn: 5.0),
            .failed(.notConnected)
        ]
        for state in states {
            #expect(!state.description.isEmpty)
        }
    }

    @Test("Disconnected description is correct")
    func disconnectedDescription() {
        #expect(ConnectionState.disconnected.description == "disconnected")
    }

    @Test("Reconnecting description includes attempt number")
    func reconnectingDescription() {
        let state = ConnectionState.reconnecting(attempt: 2, nextRetryIn: 3.5)
        #expect(state.description.contains("3"))
        #expect(state.description.contains("3.5"))
    }

    @Test("Failed description includes error info")
    func failedDescription() {
        let state = ConnectionState.failed(.notConnected)
        #expect(state.description.contains("failed"))
    }

    // MARK: - Hashable

    @Test("Equal states hash equally")
    func equalStatesHashEqually() {
        let a = ConnectionState.connected
        let b = ConnectionState.connected
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different reconnecting attempts are not equal")
    func differentReconnectingAttempts() {
        let a = ConnectionState.reconnecting(attempt: 1, nextRetryIn: 1.0)
        let b = ConnectionState.reconnecting(attempt: 2, nextRetryIn: 1.0)
        #expect(a != b)
    }

    @Test("Different failed errors are not equal")
    func differentFailedErrors() {
        let a = ConnectionState.failed(.notConnected)
        let b = ConnectionState.failed(.alreadyConnected)
        #expect(a != b)
    }
}
