// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - Client Integration

@Suite("IcecastAuthentication — Client Integration")
struct AuthClientIntegrationTests {

    @Test("Bearer token appears in PUT request")
    func bearerInPutRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .bearer(token: "test-token-123")
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Authorization: Bearer test-token-123"))
        await client.disconnect()
    }

    @Test("QueryToken modifies mountpoint in PUT request")
    func queryTokenInPutRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .queryToken(key: "token", value: "secret")
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("PUT /live.mp3?token=secret"))
        await client.disconnect()
    }

    @Test("Digest auth handles 401 challenge and retries")
    func digestAuthChallengeRetry() async throws {
        let mock = MockTransportConnection()

        let challengeResponse = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"testnonce123\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))

        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .digest(
                username: "source", password: "hackme"
            )
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        let retryRequest = String(decoding: sentData[1], as: UTF8.self)
        #expect(retryRequest.contains("Authorization: Digest"))
        #expect(retryRequest.contains("username=\"source\""))
        #expect(retryRequest.contains("realm=\"icecast\""))
        await client.disconnect()
    }

    @Test("digestAuthFailed thrown when server rejects digest response")
    func digestAuthFailedOnSecond401() async throws {
        let mock = MockTransportConnection()

        let challengeResponse = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"nonce1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))

        await mock.enqueueResponse(
            Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .digest(
                username: "source", password: "wrong"
            )
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        do {
            try await client.connect()
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed = error {
                // Expected
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("tokenExpired is non-recoverable error")
    func tokenExpiredNonRecoverable() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .bearer(token: "expired-token")
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        do {
            try await client.connect()
            Issue.record("Expected tokenExpired error")
        } catch let error as IcecastError {
            #expect(error == .tokenExpired)
        }
    }

    @Test("tokenInvalid thrown on 403 with bearer auth")
    func tokenInvalidOn403() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 403 Forbidden\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .bearer(token: "invalid-token")
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        do {
            try await client.connect()
            Issue.record("Expected tokenInvalid error")
        } catch let error as IcecastError {
            #expect(error == .tokenInvalid)
        }
    }

    @Test("Bearer token appears in SOURCE request")
    func bearerInSourceRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastSOURCE,
            authentication: .bearer(token: "source-token")
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("SOURCE /live.mp3"))
        #expect(request.contains("Authorization: Bearer source-token"))
        await client.disconnect()
    }

    @Test("QueryToken modifies mountpoint in SOURCE request")
    func queryTokenInSourceRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastSOURCE,
            authentication: .queryToken(key: "auth", value: "abc")
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("SOURCE /live.mp3?auth=abc"))
        await client.disconnect()
    }

    @Test("Digest auth handles 401 challenge in SOURCE mode")
    func digestAuthSourceRetry() async throws {
        let mock = MockTransportConnection()

        let challengeResponse = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"srcnonce\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastSOURCE,
            authentication: .digest(
                username: "source", password: "hackme"
            )
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        let retryRequest = String(decoding: sentData[1], as: UTF8.self)
        #expect(retryRequest.contains("Authorization: Digest"))
        #expect(retryRequest.contains("SOURCE /live.mp3"))
        await client.disconnect()
    }

    @Test("Basic auth in SOURCE request via authentication property")
    func basicAuthInSourceRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastSOURCE,
            authentication: .basic(
                username: "source", password: "hackme"
            )
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("SOURCE /live.mp3"))
        #expect(request.contains("Authorization: Basic"))
        await client.disconnect()
    }
}

// MARK: - Digest Auth Wire Format

@Suite("IcecastAuthentication — Digest Wire Format")
struct AuthDigestWireFormatTests {

    @Test("Digest auth first request has no Authorization header")
    func digestFirstRequestNoAuth() async throws {
        let mock = MockTransportConnection()

        let challengeResponse = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastPUT,
            authentication: .digest(
                username: "source", password: "hackme"
            )
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        let firstRequest = String(decoding: sentData[0], as: UTF8.self)
        #expect(!firstRequest.contains("Authorization:"))
        await client.disconnect()
    }

    @Test("Digest retry creates new connection when server closes after 401")
    func digestRetryNewConnection() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )

        let challengeResponse = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3"
        )

        let proto = IcecastProtocol()
        let newConn = try await proto.performPUTHandshake(
            connection: mock,
            configuration: config,
            authentication: .digest(
                username: "source", password: "hackme"
            ),
            connectionFactory: { retryMock }
        )

        #expect(newConn != nil)

        let connectedHost = await retryMock.lastConnectHost
        #expect(connectedHost == "localhost")
        let connectedPort = await retryMock.lastConnectPort
        #expect(connectedPort == 8000)

        let retryData = await retryMock.sentData
        #expect(retryData.count == 1)
        let retryRequest = String(
            decoding: retryData[0], as: UTF8.self
        )
        #expect(retryRequest.contains("Authorization: Digest"))
        #expect(retryRequest.contains("username=\"source\""))
    }

    @Test("Digest SOURCE first request has no Authorization header")
    func digestSourceFirstRequestNoAuth() async throws {
        let mock = MockTransportConnection()

        let challengeResponse = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let config = IcecastConfiguration(
            host: "localhost",
            port: 8000,
            mountpoint: "/live.mp3",
            protocolMode: .icecastSOURCE,
            authentication: .digest(
                username: "source", password: "hackme"
            )
        )
        let creds = IcecastCredentials(password: "unused")
        let client = IcecastClient(
            configuration: config,
            credentials: creds,
            connectionFactory: { mock }
        )

        try await client.connect()
        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        let firstRequest = String(decoding: sentData[0], as: UTF8.self)
        #expect(firstRequest.contains("SOURCE /live.mp3"))
        #expect(!firstRequest.contains("Authorization:"))
        await client.disconnect()
    }
}
