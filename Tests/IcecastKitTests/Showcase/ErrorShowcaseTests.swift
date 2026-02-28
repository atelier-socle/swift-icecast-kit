// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Showcase — Error Scenarios")
struct ErrorShowcaseTests {

    private static let config = IcecastConfiguration(
        host: "radio.example.com",
        port: 8000,
        mountpoint: "/live.mp3"
    )
    private static let credentials = IcecastCredentials(password: "hackme")

    // MARK: - Test 12: Complete Error Scenario Coverage (split into focused tests)

    /// 401 Unauthorized → authenticationFailed with correct status code.
    /// Verifies client transitions to failed state.
    @Test("Error: 401 Unauthorized maps to authenticationFailed")
    func authenticationFailed() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic\r\n\r\n".utf8)
        )
        let client = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        do {
            try await client.connect()
            Issue.record("Expected authenticationFailed error")
        } catch let error as IcecastError {
            if case .authenticationFailed(let code, _) = error {
                #expect(code == 401)
            } else {
                Issue.record("Expected authenticationFailed, got \(error)")
            }
            #expect(!error.description.isEmpty)
        }
        let state = await client.state
        if case .failed = state {
        } else {
            Issue.record("Expected failed state, got \(state)")
        }
    }

    /// 403 with "mountpoint in use" → mountpointInUse error.
    @Test("Error: 403 Mountpoint in use")
    func mountpointInUse() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 403 Mountpoint in use\r\n\r\n".utf8)
        )
        let client = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        do {
            try await client.connect()
            Issue.record("Expected mountpointInUse error")
        } catch let error as IcecastError {
            if case .mountpointInUse = error {
            } else {
                Issue.record("Expected mountpointInUse, got \(error)")
            }
            #expect(!error.description.isEmpty)
        }
    }

    /// 403 with "content type" → contentTypeNotSupported error.
    @Test("Error: 403 Content-Type not supported")
    func contentTypeNotSupported() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 403 Content-Type not supported\r\n\r\n".utf8)
        )
        let client = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        do {
            try await client.connect()
            Issue.record("Expected contentTypeNotSupported error")
        } catch let error as IcecastError {
            if case .contentTypeNotSupported = error {
            } else {
                Issue.record("Expected contentTypeNotSupported, got \(error)")
            }
            #expect(!error.description.isEmpty)
        }
    }

    /// 403 with "too many sources" → tooManySources error.
    @Test("Error: 403 Too many sources")
    func tooManySources() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 403 Too many sources connected\r\n\r\n".utf8)
        )
        let client = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        do {
            try await client.connect()
            Issue.record("Expected tooManySources error")
        } catch let error as IcecastError {
            if case .tooManySources = error {
            } else {
                Issue.record("Expected tooManySources, got \(error)")
            }
            #expect(!error.description.isEmpty)
        }
    }

    /// 500 Internal Server Error → serverError with correct status code.
    @Test("Error: 500 Server Error")
    func serverError() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.1 500 Internal Server Error\r\n\r\n".utf8)
        )
        let client = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        do {
            try await client.connect()
            Issue.record("Expected serverError")
        } catch let error as IcecastError {
            if case .serverError(let code, _) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected serverError, got \(error)")
            }
            #expect(!error.description.isEmpty)
        }
    }

    /// Send while disconnected → notConnected.
    /// UpdateMetadata while disconnected → notConnected.
    /// Connect while connected → alreadyConnected.
    @Test("Error: State enforcement errors")
    func stateEnforcementErrors() async throws {
        // Send while disconnected
        let mock1 = MockTransportConnection()
        let client1 = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock1 }
        )
        do {
            try await client1.send(Data("audio".utf8))
            Issue.record("Expected notConnected")
        } catch let error as IcecastError {
            #expect(error == .notConnected)
        }

        // UpdateMetadata while disconnected
        do {
            try await client1.updateMetadata(ICYMetadata(streamTitle: "Test"))
            Issue.record("Expected notConnected for metadata update")
        } catch let error as IcecastError {
            #expect(error == .notConnected)
        }

        // Connect while connected → alreadyConnected
        let mock2 = MockTransportConnection()
        await mock2.enqueueResponses([
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8),
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        ])
        let client2 = IcecastClient(
            configuration: Self.config,
            credentials: Self.credentials,
            reconnectPolicy: .none,
            connectionFactory: { mock2 }
        )
        try await client2.connect()
        do {
            try await client2.connect()
            Issue.record("Expected alreadyConnected")
        } catch let error as IcecastError {
            #expect(error == .alreadyConnected)
        }
        await client2.disconnect()
    }

    /// Verify all IcecastError cases have non-empty, informative descriptions.
    @Test("Error: All error descriptions are non-empty")
    func allErrorDescriptionsNonEmpty() {
        let allErrors: [IcecastError] = [
            .connectionFailed(host: "h", port: 1, reason: "r"),
            .connectionTimeout(seconds: 5),
            .connectionLost(reason: "r"),
            .tlsError(reason: "r"),
            .dnsResolutionFailed(host: "h"),
            .authenticationFailed(statusCode: 401, message: "m"),
            .credentialsRequired,
            .protocolNegotiationFailed(tried: ["PUT"]),
            .unexpectedResponse(statusCode: 999, message: "m"),
            .invalidResponse(reason: "r"),
            .emptyResponse,
            .serverError(statusCode: 500, message: "m"),
            .mountpointInUse("/mp"),
            .mountpointNotFound("/mp"),
            .contentTypeNotSupported("ct"),
            .tooManySources,
            .invalidMountpoint("mp"),
            .metadataEncodingFailed(reason: "r"),
            .metadataTooLong(length: 5000, maxLength: 4080),
            .metadataUpdateFailed(reason: "r"),
            .adminAPIUnavailable,
            .notConnected,
            .alreadyConnected,
            .alreadyStreaming,
            .invalidState(current: "a", expected: "b"),
            .sendFailed(reason: "r"),
            .invalidAudioData(reason: "r")
        ]

        for error in allErrors {
            #expect(
                !error.description.isEmpty,
                "Error \(error) should have a non-empty description")
        }
    }
}
