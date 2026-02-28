// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

/// Thread-safe event collector for reconnection showcase.
private actor ReconnectionEventCollector {
    var events: [ConnectionEvent] = []

    func append(_ event: ConnectionEvent) {
        events.append(event)
    }
}

@Suite("Showcase — Reconnection")
struct ReconnectionShowcaseTests {

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)

    private static func collectEvents(
        from client: IcecastClient,
        into collector: ReconnectionEventCollector
    ) -> Task<Void, Never> {
        Task {
            for await event in client.events {
                await collector.append(event)
            }
        }
    }

    // MARK: - Test 5: Reconnection with Exponential Backoff

    /// Demonstrates auto-reconnection after connection loss:
    /// 1. Connect and start streaming
    /// 2. Simulate connection loss mid-stream (mock throws on send)
    /// 3. Client enters reconnecting state
    /// 4. Verify retry attempts with the reconnection policy
    /// 5. After reconnection succeeds, verify streaming resumes
    /// 6. Verify statistics reflect the reconnection
    @Test("Reconnection with exponential backoff")
    func reconnectionWithExponentialBackoff() async throws {
        let mock = MockTransportConnection()
        // Initial PUT handshake + after-reconnection handshake
        await mock.enqueueResponses([Self.putOKResponse, Self.putOKResponse])

        // Use a fast reconnect policy for test speed (very short delays, no jitter)
        let reconnectPolicy = ReconnectPolicy(
            maxRetries: 3,
            initialDelay: 0.02,
            maxDelay: 0.1,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0
        )

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com",
                port: 8000,
                mountpoint: "/live.mp3"
            ),
            credentials: IcecastCredentials(password: "hackme"),
            reconnectPolicy: reconnectPolicy,
            connectionFactory: { mock }
        )

        let collector = ReconnectionEventCollector()
        let eventTask = Self.collectEvents(from: client, into: collector)

        // --- Step 1: Connect and stream some data ---
        try await client.connect()
        try await client.send(Data(repeating: 0xAA, count: 1024))
        let stateBeforeLoss = await client.state
        #expect(stateBeforeLoss == .streaming)

        // --- Step 2: Simulate connection loss ---
        // Set send to fail → triggers handleConnectionLoss → starts reconnection loop
        await mock.setSendError(.connectionLost(reason: "broken pipe"))
        do { try await client.send(Data(repeating: 0xBB, count: 512)) } catch {}

        // --- Step 3: Wait for reconnection to complete ---
        // The mock's connectError is nil, so the reconnection will succeed
        // after the first retry (send error is still set but connect will succeed).
        // Clear the send error so reconnection handshake doesn't fail.
        await mock.setSendError(nil)

        try await Task.sleep(nanoseconds: 400_000_000)

        // --- Step 4: Verify reconnection succeeded ---
        let stateAfterReconnect = await client.state
        let isReconnected: Bool = {
            switch stateAfterReconnect {
            case .connected, .streaming: return true
            default: return false
            }
        }()
        #expect(isReconnected)

        // --- Step 5: Verify statistics reflect the reconnection ---
        let stats = await client.statistics
        // bytesSent should include the 1024 bytes sent before loss
        #expect(stats.bytesSent >= 1024)
        // At least 1 send error was recorded
        #expect(stats.sendErrorCount >= 1)

        await client.disconnect()
        try await Task.sleep(nanoseconds: 50_000_000)
        eventTask.cancel()

        // --- Step 6: Verify reconnection events were emitted ---
        let events = await collector.events
        let reconnectingEvents = events.filter {
            if case .reconnecting = $0 { return true }
            return false
        }
        // At least one reconnecting event should have been emitted
        #expect(!reconnectingEvents.isEmpty)
    }
}
