// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - URL Credential Parsing

@Suite("IcecastAuthentication — URL Parsing")
struct AuthURLParsingTests {

    @Test("fromURL extracts credentials from URL with user:password")
    func fromURLWithCredentials() {
        let auth = IcecastAuthentication.fromURL(
            "http://admin:secret@radio.example.com:8000/live.mp3"
        )
        #expect(auth == .basic(username: "admin", password: "secret"))
    }

    @Test("fromURL returns nil for URL without credentials")
    func fromURLWithoutCredentials() {
        let auth = IcecastAuthentication.fromURL(
            "http://radio.example.com:8000/live.mp3"
        )
        #expect(auth == nil)
    }

    @Test("fromURL returns nil for malformed URL")
    func fromURLMalformed() {
        let auth = IcecastAuthentication.fromURL("not a valid url ::::")
        #expect(auth == nil)
    }

    @Test("fromURL uses 'source' as default username when only password present")
    func fromURLDefaultUsername() {
        // URLComponents with user but no password returns nil password
        let auth = IcecastAuthentication.fromURL(
            "http://:secret@radio.example.com:8000/live.mp3"
        )
        #expect(auth == .basic(username: "source", password: "secret"))
    }

    @Test("stripCredentials removes user:password from URL")
    func stripCredentialsRemovesCreds() {
        let result = IcecastAuthentication.stripCredentials(
            from: "http://admin:secret@radio.example.com:8000/live.mp3"
        )
        #expect(!result.contains("admin"))
        #expect(!result.contains("secret"))
        #expect(result.contains("radio.example.com"))
        #expect(result.contains("/live.mp3"))
    }

    @Test("stripCredentials returns URL unchanged when no credentials")
    func stripCredentialsNoCreds() {
        let url = "http://radio.example.com:8000/live.mp3"
        let result = IcecastAuthentication.stripCredentials(from: url)
        #expect(result == url)
    }

    @Test("stripCredentials handles malformed URL gracefully")
    func stripCredentialsMalformed() {
        let url = "not a valid url ::::"
        let result = IcecastAuthentication.stripCredentials(from: url)
        #expect(result == url)
    }
}

// MARK: - Credential Bridge

@Suite("IcecastAuthentication — Credential Bridge")
struct AuthCredentialBridgeTests {

    @Test("basic auth converts to IcecastCredentials")
    func basicToCredentials() {
        let auth = IcecastAuthentication.basic(
            username: "source", password: "hackme"
        )
        let creds = auth.credentials
        #expect(creds?.username == "source")
        #expect(creds?.password == "hackme")
    }

    @Test("digest auth converts to IcecastCredentials")
    func digestToCredentials() {
        let auth = IcecastAuthentication.digest(
            username: "admin", password: "secret"
        )
        let creds = auth.credentials
        #expect(creds?.username == "admin")
        #expect(creds?.password == "secret")
    }

    @Test("bearer auth returns nil credentials")
    func bearerToCredentials() {
        let auth = IcecastAuthentication.bearer(token: "token")
        #expect(auth.credentials == nil)
    }

    @Test("queryToken auth returns nil credentials")
    func queryTokenToCredentials() {
        let auth = IcecastAuthentication.queryToken(
            key: "k", value: "v"
        )
        #expect(auth.credentials == nil)
    }

    @Test("shoutcast auth converts to IcecastCredentials")
    func shoutcastToCredentials() {
        let auth = IcecastAuthentication.shoutcast(password: "sc-pass")
        let creds = auth.credentials
        #expect(creds?.password == "sc-pass")
    }

    @Test("shoutcastV2 auth converts to IcecastCredentials")
    func shoutcastV2ToCredentials() {
        let auth = IcecastAuthentication.shoutcastV2(
            password: "v2-pass", streamId: 1
        )
        let creds = auth.credentials
        #expect(creds?.password == "v2-pass")
    }

    @Test("IcecastCredentials.authentication returns .basic")
    func credentialsToAuthentication() {
        let creds = IcecastCredentials(
            username: "source", password: "hackme"
        )
        let auth = creds.authentication
        #expect(auth == .basic(username: "source", password: "hackme"))
    }
}

// MARK: - Authorization Header

@Suite("IcecastAuthentication — Authorization Header")
struct AuthHeaderTests {

    @Test("basic auth returns Basic header")
    func basicAuthHeader() {
        let auth = IcecastAuthentication.basic(
            username: "source", password: "hackme"
        )
        let header = auth.initialAuthorizationHeader()
        #expect(header != nil)
        #expect(header?.hasPrefix("Basic ") == true)
    }

    @Test("bearer auth returns Bearer header")
    func bearerAuthHeader() {
        let auth = IcecastAuthentication.bearer(token: "mytoken")
        let header = auth.initialAuthorizationHeader()
        #expect(header == "Bearer mytoken")
    }

    @Test("digest auth returns nil initial header")
    func digestAuthHeader() {
        let auth = IcecastAuthentication.digest(
            username: "u", password: "p"
        )
        #expect(auth.initialAuthorizationHeader() == nil)
    }

    @Test("queryToken auth returns nil initial header")
    func queryTokenAuthHeader() {
        let auth = IcecastAuthentication.queryToken(
            key: "k", value: "v"
        )
        #expect(auth.initialAuthorizationHeader() == nil)
    }
}

// MARK: - Protocol Edge Cases

@Suite("IcecastAuthentication — Protocol Edge Cases")
struct AuthProtocolEdgeCaseTests {

    private func connectedMock() async throws -> MockTransportConnection {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        return mock
    }

    @Test("Digest auth fails when 401 missing WWW-Authenticate header")
    func digestMissingWWWAuthenticate() async throws {
        let mock = try await connectedMock()
        await mock.enqueueResponse(
            Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        do {
            try await proto.performPUTHandshake(
                connection: mock,
                configuration: IcecastConfiguration(
                    host: "localhost",
                    port: 8000,
                    mountpoint: "/live.mp3"
                ),
                authentication: .digest(
                    username: "source", password: "hackme"
                )
            )
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed(let reason) = error {
                #expect(reason.contains("WWW-Authenticate"))
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("Digest auth fails with unparseable challenge")
    func digestUnparseableChallenge() async throws {
        let mock = try await connectedMock()
        let response = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest nonce=\"abc\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(response.utf8))

        let proto = IcecastProtocol()
        do {
            try await proto.performPUTHandshake(
                connection: mock,
                configuration: IcecastConfiguration(
                    host: "localhost",
                    port: 8000,
                    mountpoint: "/live.mp3"
                ),
                authentication: .digest(
                    username: "u", password: "p"
                )
            )
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed(let reason) = error {
                #expect(reason.contains("parse"))
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("PUT handshake with auth handles 100 Continue")
    func putAuthWith100Continue() async throws {
        let mock = try await connectedMock()
        await mock.enqueueResponse(
            Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        try await proto.performPUTHandshake(
            connection: mock,
            configuration: IcecastConfiguration(
                host: "localhost",
                port: 8000,
                mountpoint: "/live.mp3"
            ),
            authentication: .basic(
                username: "source", password: "hackme"
            )
        )
    }

    @Test("Digest retry with 100 Continue then 200")
    func digestRetryWith100Continue() async throws {
        let mock = try await connectedMock()

        let challenge = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"ice\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challenge.utf8))
        await mock.enqueueResponse(
            Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
        )
        await mock.enqueueResponse(
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        try await proto.performPUTHandshake(
            connection: mock,
            configuration: IcecastConfiguration(
                host: "localhost",
                port: 8000,
                mountpoint: "/live.mp3"
            ),
            authentication: .digest(
                username: "source", password: "hackme"
            )
        )
    }

    @Test("Digest auth fails with empty response after retry")
    func digestEmptyResponseAfterRetry() async throws {
        let mock = try await connectedMock()

        let challenge = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"ice\", nonce=\"n1\"",
            "",
            ""
        ].joined(separator: "\r\n")
        await mock.enqueueResponse(Data(challenge.utf8))
        // Empty response after digest retry
        await mock.enqueueResponse(Data())

        let proto = IcecastProtocol()
        do {
            try await proto.performPUTHandshake(
                connection: mock,
                configuration: IcecastConfiguration(
                    host: "localhost",
                    port: 8000,
                    mountpoint: "/live.mp3"
                ),
                authentication: .digest(
                    username: "u", password: "p"
                )
            )
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed(let reason) = error {
                #expect(reason.contains("Empty"))
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }
    }

    @Test("Auth path with unexpected status code throws error")
    func authPathUnexpectedStatus() async throws {
        let mock = try await connectedMock()
        await mock.enqueueResponse(
            Data("HTTP/1.1 302 Found\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        do {
            try await proto.performPUTHandshake(
                connection: mock,
                configuration: IcecastConfiguration(
                    host: "localhost",
                    port: 8000,
                    mountpoint: "/live.mp3"
                ),
                authentication: .basic(
                    username: "source", password: "hackme"
                )
            )
            Issue.record("Expected unexpectedResponse error")
        } catch let error as IcecastError {
            if case .unexpectedResponse(let code, _) = error {
                #expect(code == 302)
            } else {
                Issue.record(
                    "Expected unexpectedResponse, got \(error)"
                )
            }
        }
    }

    @Test("Bearer auth with server error falls through")
    func bearerWithServerError() async throws {
        let mock = try await connectedMock()
        await mock.enqueueResponse(
            Data("HTTP/1.1 500 Internal Server Error\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        do {
            try await proto.performPUTHandshake(
                connection: mock,
                configuration: IcecastConfiguration(
                    host: "localhost",
                    port: 8000,
                    mountpoint: "/live.mp3"
                ),
                authentication: .bearer(token: "tok")
            )
            Issue.record("Expected serverError")
        } catch let error as IcecastError {
            if case .serverError = error {
                // Expected
            } else {
                Issue.record("Expected serverError, got \(error)")
            }
        }
    }
}
