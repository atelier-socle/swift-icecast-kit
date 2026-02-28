// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Concurrency")
struct ConcurrencyShowcaseTests {

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)

    // MARK: - Test 11: Concurrent Metadata Updates and Sends

    /// Demonstrates thread safety with concurrent operations:
    /// 1. Connect to server
    /// 2. Launch 10 concurrent tasks each updating metadata
    /// 3. Launch 5 concurrent tasks each sending data
    /// 4. Verify no data races, no crashes
    /// 5. Verify final statistics are consistent
    @Test("Concurrent metadata updates and sends")
    func concurrentMetadataUpdatesAndSends() async throws {
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

        // --- Step 2: Send initial data to transition to .streaming ---
        try await client.send(Data(repeating: 0x00, count: 128))

        // --- Step 3: Launch concurrent operations ---
        // All operations run simultaneously — actor isolation ensures thread safety
        await withTaskGroup(of: Void.self) { group in
            // 10 concurrent metadata updates
            for i in 0..<10 {
                group.addTask {
                    try? await client.updateMetadata(
                        ICYMetadata(streamTitle: "Concurrent Track \(i)")
                    )
                }
            }

            // 5 concurrent sends
            for i in 0..<5 {
                group.addTask {
                    try? await client.send(Data(repeating: UInt8(i), count: 256))
                }
            }
        }

        // --- Step 4: Verify no crashes occurred (if we reach here, no data races) ---
        let state = await client.state
        #expect(state == .streaming)

        // --- Step 5: Verify final statistics are consistent ---
        let stats = await client.statistics

        // All 10 metadata updates should have been recorded
        #expect(stats.metadataUpdateCount == 10)

        // Initial 128 bytes + 5 concurrent sends of 256 bytes = 128 + 1280 = 1408
        #expect(stats.bytesSent == 1408)
        #expect(stats.bytesTotal == 1408)

        // No reconnection attempts
        #expect(stats.reconnectionCount == 0)
        #expect(stats.sendErrorCount == 0)

        await client.disconnect()
    }
}
