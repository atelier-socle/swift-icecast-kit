// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("IcecastAuthentication — Relay Integration")
struct AuthRelayIntegrationTests {

    @Test("URL-embedded credentials used by relay")
    func urlEmbeddedCredentialsRelay() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xAA, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://admin:secret@localhost:8000/live.mp3"
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Authorization: Basic"))
        #expect(!request.contains("admin:secret@"))
        await relay.disconnect()
    }

    @Test("Relay with explicit digest authentication")
    func relayDigestAuth() async throws {
        let mock = MockTransportConnection()

        let challengeResponse = [
            "HTTP/1.0 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"relay\", nonce=\"relaynonce\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challengeResponse.utf8))

        let okResponse = [
            "HTTP/1.0 200 OK",
            "content-type: audio/mpeg",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(okResponse.utf8))
        await mock.enqueueResponse(Data(repeating: 0xBB, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .digest(
                username: "admin", password: "secret"
            )
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        let retryRequest = String(decoding: sentData[1], as: UTF8.self)
        #expect(retryRequest.contains("Authorization: Digest"))
        #expect(retryRequest.contains("username=\"admin\""))
        await relay.disconnect()
    }

    @Test("Relay with explicit bearer authentication")
    func relayBearerAuth() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xCC, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .bearer(token: "relay-token")
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Authorization: Bearer relay-token"))
        await relay.disconnect()
    }

    @Test("Relay with queryToken modifies mountpoint")
    func relayQueryToken() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xDD, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .queryToken(key: "key", value: "val")
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("GET /live.mp3?key=val"))
        await relay.disconnect()
    }

    @Test("Relay digest auth fails when 401 missing WWW-Authenticate")
    func relayDigestMissingHeader() async throws {
        let mock = MockTransportConnection()

        await mock.enqueueResponse(
            Data("HTTP/1.0 401 Unauthorized\r\n\r\n".utf8)
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .digest(
                username: "admin", password: "secret"
            )
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        do {
            try await relay.connect()
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed(let reason) = error {
                #expect(reason.contains("WWW-Authenticate"))
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("Relay digest auth fails on second 401")
    func relayDigestRejected() async throws {
        let mock = MockTransportConnection()

        let challenge = [
            "HTTP/1.0 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"relay\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challenge.utf8))
        await mock.enqueueResponse(
            Data("HTTP/1.0 401 Unauthorized\r\n\r\n".utf8)
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .digest(
                username: "admin", password: "wrong"
            )
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        do {
            try await relay.connect()
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed(let reason) = error {
                #expect(reason.contains("rejected"))
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("Relay digest auth fails with unparseable challenge")
    func relayDigestUnparseable() async throws {
        let mock = MockTransportConnection()

        let challenge = [
            "HTTP/1.0 401 Unauthorized",
            "WWW-Authenticate: Digest nonce=\"abc\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challenge.utf8))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .digest(
                username: "admin", password: "secret"
            )
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        do {
            try await relay.connect()
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed(let reason) = error {
                #expect(reason.contains("parse"))
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("Relay digest auth fails when retry receives error")
    func relayDigestRetryReceiveError() async throws {
        let mock = MockTransportConnection()

        let challenge = [
            "HTTP/1.0 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"ice\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challenge.utf8))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .digest(
                username: "admin", password: "secret"
            )
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        do {
            try await relay.connect()
            Issue.record("Expected digestAuthFailed error")
        } catch {
            // Expected — no response after Digest authentication
        }
    }

    @Test("Relay with explicit basic credentials via authentication")
    func relayBasicAuthExplicit() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data(
                "HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg\r\n\r\n".utf8
            )
        )
        await mock.enqueueResponse(Data(repeating: 0xEE, count: 10))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            authentication: .basic(
                username: "user", password: "pass"
            )
        )
        let relay = IcecastRelay(
            configuration: config,
            transportFactory: { mock }
        )

        try await relay.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Authorization: Basic"))
        await relay.disconnect()
    }
}
