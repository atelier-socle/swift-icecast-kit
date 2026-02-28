// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Monitoring")
struct MonitoringShowcaseTests {

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)

    // MARK: - Test 10: Long-Running Stream Statistics

    /// Demonstrates connection statistics accuracy over a simulated session:
    /// 1. Connect and stream data (simulated high volume)
    /// 2. Verify bytesSent matches total data sent
    /// 3. Verify bytesTotal tracks all bytes
    /// 4. Verify metadataUpdateCount and reconnectionCount
    /// 5. Verify duration tracking via connectedSince
    /// 6. Verify monitor can be accessed through the client
    @Test("Long-running stream statistics accuracy")
    func longRunningStreamStatistics() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com",
                port: 8000,
                mountpoint: "/live.mp3"
            ),
            credentials: IcecastCredentials(password: "hackme"),
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )

        // --- Step 1: Connect ---
        try await client.connect()

        // Verify connectedSince is set after connection
        let statsAfterConnect = await client.statistics
        #expect(statsAfterConnect.connectedSince != nil)
        #expect(statsAfterConnect.bytesSent == 0)

        // --- Step 2: Send a large amount of data in chunks ---
        // Simulate 128 kbps × 5 seconds = 80,000 bytes
        let totalTargetBytes = 80_000
        let chunkSize = 4000
        let chunks = totalTargetBytes / chunkSize

        for _ in 0..<chunks {
            try await client.send(Data(repeating: 0xAA, count: chunkSize))
        }

        // --- Step 3: Verify bytesSent matches exactly ---
        let statsAfterSend = await client.statistics
        let expectedBytes = UInt64(chunks * chunkSize)
        #expect(statsAfterSend.bytesSent == expectedBytes)
        #expect(statsAfterSend.bytesTotal == expectedBytes)

        // --- Step 4: Update metadata multiple times ---
        for i in 0..<5 {
            try await client.updateMetadata(ICYMetadata(streamTitle: "Track \(i + 1)"))
        }

        let statsAfterMetadata = await client.statistics
        #expect(statsAfterMetadata.metadataUpdateCount == 5)

        // --- Step 5: Verify duration is positive ---
        #expect(statsAfterMetadata.duration > 0)
        #expect(statsAfterMetadata.connectedSince != nil)

        // --- Step 6: Verify reconnection count starts at 0 ---
        #expect(statsAfterMetadata.reconnectionCount == 0)

        // --- Step 7: Disconnect and verify connectedSince is cleared ---
        await client.disconnect()
        let statsAfterDisconnect = await client.statistics
        #expect(statsAfterDisconnect.connectedSince == nil)

        // bytesSent is preserved after disconnect (monitor is not reset)
        #expect(statsAfterDisconnect.bytesSent == expectedBytes)
    }
}
