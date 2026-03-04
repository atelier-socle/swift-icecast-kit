// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("ProtocolNegotiator — Digest Auth Paths")
struct ProtocolNegotiatorDigestTests {

    let credentials = IcecastCredentials(password: "unused")

    private func digestChallenge(nonce: String = "n1") -> Data {
        let lines = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"\(nonce)\"",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(lines.utf8)
    }

    private static let ok = Data("HTTP/1.1 200 OK\r\n\r\n".utf8)

    // MARK: - Explicit Mode — fallbackConnection stored

    @Test("PUT digest auth stores fallbackConnection when retry uses new connection")
    func putDigestFallbackConnection() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(digestChallenge())

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(Self.ok)

        let putConfig = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT
        )

        let negotiator = ProtocolNegotiator { retryMock }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: putConfig,
            credentials: credentials,
            authentication: .digest(username: "source", password: "hackme")
        )

        #expect(mode == .icecastPUT)
        let fb = await negotiator.fallbackConnection
        #expect(fb != nil)
        let mockClosed = await mock.closeCallCount
        #expect(mockClosed >= 1)
    }

    @Test("SOURCE digest auth stores fallbackConnection when retry uses new connection")
    func sourceDigestFallbackConnection() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(digestChallenge())

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(Self.ok)

        let sourceConfig = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastSOURCE
        )

        let negotiator = ProtocolNegotiator { retryMock }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: sourceConfig,
            credentials: credentials,
            authentication: .digest(username: "source", password: "hackme")
        )

        #expect(mode == .icecastSOURCE)
        let fb = await negotiator.fallbackConnection
        #expect(fb != nil)
        let mockClosed = await mock.closeCallCount
        #expect(mockClosed >= 1)
    }

    @Test("Auto mode digest auth stores fallbackConnection on PUT success")
    func autoDigestFallbackConnection() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(digestChallenge())

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(Self.ok)

        let autoConfig = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .auto
        )

        let negotiator = ProtocolNegotiator { retryMock }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: autoConfig,
            credentials: credentials,
            authentication: .digest(username: "source", password: "hackme")
        )

        #expect(mode == .icecastPUT)
        let fb = await negotiator.fallbackConnection
        #expect(fb != nil)
        let mockClosed = await mock.closeCallCount
        #expect(mockClosed >= 1)
    }

    @Test("Auto fallback to SOURCE with digest keep-alive stores newConnection")
    func autoDigestFallbackToSourceKeepAlive() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        // PUT → empty response → auto falls back to SOURCE
        await mock.enqueueResponse(Data())

        // factoryMock: used for SOURCE fallback connection.
        // Queues 401 challenge. On reconnect, queues 200 OK.
        // Since onConnect fires on the first connect too, the queue
        // will be [401, 200] — digest retry succeeds via keep-alive.
        let factoryMock = MockTransportConnection()
        await factoryMock.enqueueResponse(digestChallenge())
        await factoryMock.setOnConnect { m in
            await m.enqueueResponse(Self.ok)
        }

        let autoConfig = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .auto
        )

        let negotiator = ProtocolNegotiator { factoryMock }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: autoConfig,
            credentials: credentials,
            authentication: .digest(username: "source", password: "hackme")
        )

        #expect(mode == .icecastSOURCE)
        let fb = await negotiator.fallbackConnection
        #expect(fb != nil)
    }
}
