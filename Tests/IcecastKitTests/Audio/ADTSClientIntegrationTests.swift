// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("IcecastClient — ADTS Wrapping")
struct ADTSClientIntegrationTests {

    @Test("send(rawAAC:) wraps data with ADTS header and sends")
    func sendRawAACWraps() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponses([
            Data("HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n".utf8),
            Data("HTTP/1.0 200 OK\r\n\r\n".utf8)
        ])

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "localhost",
                mountpoint: "/live.aac",
                contentType: .aac
            ),
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )

        try await client.connect()

        let rawAAC = Data(repeating: 0xAB, count: 100)
        let audioConfig = AudioConfiguration(sampleRate: 44100, channelCount: 2)
        try await client.send(rawAAC: rawAAC, audioConfiguration: audioConfig)

        // The last sent data should be an ADTS frame (7 header + 100 payload)
        let sentData = await mock.sentData
        let lastSend = sentData.last
        #expect(lastSend != nil)
        if let adtsFrame = lastSend {
            #expect(adtsFrame.count == 107)
            #expect(adtsFrame[0] == 0xFF)
            #expect(adtsFrame[1] & 0xF0 == 0xF0)
            // Verify payload is preserved at offset 7
            #expect(Array(adtsFrame[7...]) == Array(repeating: UInt8(0xAB), count: 100))
        }

        await client.disconnect()
    }

    @Test("send(rawAAC:) with invalid config throws before sending")
    func sendRawAACInvalidConfig() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponses([
            Data("HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n".utf8),
            Data("HTTP/1.0 200 OK\r\n\r\n".utf8)
        ])

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "localhost",
                mountpoint: "/live.aac",
                contentType: .aac
            ),
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )

        try await client.connect()

        let rawAAC = Data(repeating: 0x00, count: 50)
        let badConfig = AudioConfiguration(sampleRate: 43000, channelCount: 2)

        await #expect(throws: IcecastError.self) {
            try await client.send(rawAAC: rawAAC, audioConfiguration: badConfig)
        }

        await client.disconnect()
    }

    @Test("Original send() still works with pre-wrapped ADTS")
    func originalSendStillWorks() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponses([
            Data("HTTP/1.1 100 Continue\r\nContent-Length: 0\r\n\r\n".utf8),
            Data("HTTP/1.0 200 OK\r\n\r\n".utf8)
        ])

        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "localhost",
                mountpoint: "/live.aac",
                contentType: .aac
            ),
            credentials: IcecastCredentials(password: "test"),
            connectionFactory: { mock }
        )

        try await client.connect()

        // Pre-wrapped ADTS frame
        let preWrapped = Data([0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC, 0xAA, 0xBB])
        try await client.send(preWrapped)

        let sentData = await mock.sentData
        let lastSend = sentData.last
        #expect(lastSend == preWrapped)

        await client.disconnect()
    }
}
