// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("IcecastAuthentication — Digest Error Paths")
struct AuthDigestErrorPathTests {

    private func digestChallenge(nonce: String = "n1") -> Data {
        let lines = [
            "HTTP/1.1 401 Unauthorized",
            "WWW-Authenticate: Digest realm=\"icecast\", nonce=\"\(nonce)\"",
            "",
            ""
        ].joined(separator: "\r\n")
        return Data(lines.utf8)
    }

    private static let defaultConfig = IcecastConfiguration(
        host: "localhost",
        port: 8000,
        mountpoint: "/live.mp3"
    )

    @Test("Digest retry throws when no factory and send fails")
    func digestRetryNoFactory() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(digestChallenge())

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performPUTHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .digest(
                    username: "source", password: "hackme"
                ),
                connectionFactory: nil
            )
            Issue.record("Expected error")
        } catch {
            // Expected: send/receive fails with no factory fallback
        }
    }

    @Test("Digest retry closes new connection on connect failure")
    func digestRetryNewConnFailsOnConnect() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(digestChallenge())

        let failMock = MockTransportConnection()
        await failMock.setConnectError(
            IcecastError.connectionFailed(
                host: "localhost", port: 8000, reason: "refused"
            )
        )

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performPUTHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .digest(
                    username: "source", password: "hackme"
                ),
                connectionFactory: { failMock }
            )
            Issue.record("Expected connectionFailed error")
        } catch let error as IcecastError {
            if case .connectionFailed = error {
                // Expected
            } else {
                Issue.record("Expected connectionFailed, got \(error)")
            }
        }

        let failClosed = await failMock.closeCallCount
        #expect(failClosed >= 1)
    }

    @Test("Digest retry second 401 on new connection closes it")
    func digestRetrySecond401ClosesNewConn() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(digestChallenge())

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(
            Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performPUTHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .digest(
                    username: "source", password: "hackme"
                ),
                connectionFactory: { retryMock }
            )
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed = error {
                // Expected
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }

        let retryClosed = await retryMock.closeCallCount
        #expect(retryClosed >= 1)
    }

    @Test("Digest retry empty response on new connection closes it")
    func digestRetryEmptyResponseClosesNewConn() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(digestChallenge())

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(Data())

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performPUTHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .digest(
                    username: "source", password: "hackme"
                ),
                connectionFactory: { retryMock }
            )
            Issue.record("Expected digestAuthFailed error")
        } catch let error as IcecastError {
            if case .digestAuthFailed = error {
                // Expected
            } else {
                Issue.record("Expected digestAuthFailed, got \(error)")
            }
        }

        let retryClosed = await retryMock.closeCallCount
        #expect(retryClosed >= 1)
    }

    @Test("Bearer 500 falls through to handleResponse")
    func bearerServerError() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(
            Data("HTTP/1.1 500 Internal Server Error\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performPUTHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .bearer(token: "some-token")
            )
            Issue.record("Expected serverError")
        } catch let error as IcecastError {
            if case .serverError(let code, _) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected serverError, got \(error)")
            }
        }
    }

    @Test("SOURCE with advanced auth empty response throws emptyResponse")
    func sourceAdvancedAuthEmptyResponse() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(Data())

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performSOURCEHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .bearer(token: "tok")
            )
            Issue.record("Expected emptyResponse error")
        } catch let error as IcecastError {
            #expect(error == .emptyResponse)
        }
    }

    @Test("Digest retry error in response parsing closes new connection")
    func digestRetryParseErrorClosesNewConn() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(
            host: "localhost", port: 8000, useTLS: false
        )
        await mock.enqueueResponse(digestChallenge())

        let retryMock = MockTransportConnection()
        await retryMock.enqueueResponse(
            Data("NOT-HTTP garbage\r\n\r\n".utf8)
        )

        let proto = IcecastProtocol()
        do {
            _ = try await proto.performPUTHandshake(
                connection: mock,
                configuration: Self.defaultConfig,
                authentication: .digest(
                    username: "source", password: "hackme"
                ),
                connectionFactory: { retryMock }
            )
            Issue.record("Expected parse error")
        } catch {
            // Expected: parse error from invalid response
        }

        let retryClosed = await retryMock.closeCallCount
        #expect(retryClosed >= 1)
    }
}
