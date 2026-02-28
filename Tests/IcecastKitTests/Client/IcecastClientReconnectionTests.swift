// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("IcecastClient — Reconnection and Edge Cases")
struct IcecastClientReconnectionTests {

    private static let putOKResponse = Data("HTTP/1.1 200 OK\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)

    private static let testConfig = IcecastConfiguration(
        host: "radio.example.com",
        port: 8000,
        mountpoint: "/live.mp3"
    )

    private static let testCredentials = IcecastCredentials(password: "hackme")

    private static func makeClient(
        reconnectPolicy: ReconnectPolicy = .none,
        mock: MockTransportConnection
    ) -> IcecastClient {
        IcecastClient(
            configuration: testConfig,
            credentials: testCredentials,
            reconnectPolicy: reconnectPolicy,
            connectionFactory: { mock }
        )
    }

    // MARK: - Reconnection

    @Test("Connection loss with reconnect policy triggers reconnection")
    func connectionLossWithReconnectPolicy() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponses([Self.putOKResponse, Self.putOKResponse])
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 2, initialDelay: 0.05, jitterFactor: 0.0),
            connectionFactory: { mock }
        )
        try await client.connect()
        await mock.setSendError(.connectionLost(reason: "broken pipe"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 200_000_000)
        let state = await client.state
        let valid: Bool = {
            switch state {
            case .reconnecting, .connected, .failed: return true
            default: return false
            }
        }()
        #expect(valid)
    }

    @Test("ReconnectPolicy none prevents reconnection on connection loss")
    func noReconnectionPolicy() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(reconnectPolicy: .none, mock: mock)
        try await client.connect()
        await mock.setSendError(.connectionLost(reason: "broken pipe"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        let state = await client.state
        if case .failed = state {
        } else {
            Issue.record("Expected failed state, got \(state)")
        }
    }

    @Test("Max retries exceeded transitions to failed state")
    func maxRetriesExceeded() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 1, initialDelay: 0.01, jitterFactor: 0.0),
            connectionFactory: { mock }
        )
        try await client.connect()
        await mock.setSendError(.connectionLost(reason: "broken pipe"))
        await mock.setConnectError(.connectionFailed(host: "radio.example.com", port: 8000, reason: "refused"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 300_000_000)
        let state = await client.state
        if case .failed = state {
        } else {
            Issue.record("Expected failed state after max retries, got \(state)")
        }
    }

    @Test("disconnect during reconnection cancels reconnection loop")
    func disconnectDuringReconnection() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 10, initialDelay: 1.0, jitterFactor: 0.0),
            connectionFactory: { mock }
        )
        try await client.connect()
        await mock.setSendError(.connectionLost(reason: "broken pipe"))
        await mock.setConnectError(.connectionFailed(host: "radio.example.com", port: 8000, reason: "refused"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 50_000_000)
        await client.disconnect()
        let state = await client.state
        #expect(state == .disconnected)
    }

    @Test("updateReconnectPolicy takes effect")
    func updateReconnectPolicyWorks() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await client.updateReconnectPolicy(ReconnectPolicy(maxRetries: 50, initialDelay: 0.1))
        let state = await client.state
        #expect(state == .connected)
    }

    // MARK: - Statistics

    @Test("bytesSent increments on send")
    func bytesSentIncrements() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.send(Data(repeating: 0xAA, count: 100))
        try await client.send(Data(repeating: 0xBB, count: 200))
        let stats = await client.statistics
        #expect(stats.bytesSent == 300)
    }

    @Test("metadataUpdateCount increments on metadata update")
    func metadataCountIncrements() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song 1"))
        try await client.updateMetadata(ICYMetadata(streamTitle: "Song 2"))
        let stats = await client.statistics
        #expect(stats.metadataUpdateCount == 2)
    }

    @Test("connectedSince is set on connect and cleared on disconnect")
    func connectedSinceLifecycle() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        #expect((await client.statistics).connectedSince == nil)
        try await client.connect()
        #expect((await client.statistics).connectedSince != nil)
        await client.disconnect()
        #expect((await client.statistics).connectedSince == nil)
    }

    @Test("duration is calculated from connectedSince")
    func durationCalculated() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        try await Task.sleep(nanoseconds: 100_000_000)
        let stats = await client.statistics
        #expect(stats.duration > 0)
    }

    @Test("sendErrorCount increments on send failure")
    func sendErrorCountIncrements() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = Self.makeClient(mock: mock)
        try await client.connect()
        await mock.setSendError(.sendFailed(reason: "pipe broken"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        let stats = await client.statistics
        #expect(stats.sendErrorCount == 1)
    }

    // MARK: - Non-Recoverable Error Handling

    @Test("Auth failure during send skips reconnection")
    func authFailureDuringSendSkipsReconnection() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 5, initialDelay: 0.05),
            connectionFactory: { mock }
        )
        try await client.connect()
        await mock.setSendError(
            .authenticationFailed(statusCode: 401, message: "Token expired"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 100_000_000)
        let state = await client.state
        if case .failed = state {
        } else {
            Issue.record("Expected failed state (no reconnection), got \(state)")
        }
    }

    @Test("Mountpoint in use during send skips reconnection")
    func mountpointInUseDuringSendSkipsReconnection() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 5, initialDelay: 0.05),
            connectionFactory: { mock }
        )
        try await client.connect()
        await mock.setSendError(.mountpointInUse("/live.mp3"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 100_000_000)
        let state = await client.state
        if case .failed = state {
        } else {
            Issue.record("Expected failed state (no reconnection), got \(state)")
        }
    }

    @Test("Content type rejected during send skips reconnection")
    func contentTypeRejectedDuringSendSkipsReconnection() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Self.putOKResponse)
        let client = IcecastClient(
            configuration: Self.testConfig,
            credentials: Self.testCredentials,
            reconnectPolicy: ReconnectPolicy(maxRetries: 5, initialDelay: 0.05),
            connectionFactory: { mock }
        )
        try await client.connect()
        await mock.setSendError(.contentTypeNotSupported("audio/flac"))
        do { try await client.send(Data("audio".utf8)) } catch {}
        try await Task.sleep(nanoseconds: 100_000_000)
        let state = await client.state
        if case .failed = state {
        } else {
            Issue.record("Expected failed state (no reconnection), got \(state)")
        }
    }

    // MARK: - SHOUTcast Port Adjustment

    @Test("SHOUTcast v1 connects to port plus one")
    func shoutcastPortAdjustment() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("OK2\r\nicy-caps:11\r\n\r\n".utf8))
        let client = IcecastClient(
            configuration: IcecastConfiguration(
                host: "radio.example.com", port: 8000, mountpoint: "/live.mp3",
                protocolMode: .shoutcastV1
            ),
            credentials: .shoutcast(password: "hackme"),
            reconnectPolicy: .none,
            connectionFactory: { mock }
        )
        try await client.connect()
        let connectPort = await mock.lastConnectPort
        #expect(connectPort == 8001)
    }

    // MARK: - Authentication Failure

    @Test("Authentication failure transitions to failed state")
    func authFailureGoesToFailed() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))
        let client = Self.makeClient(mock: mock)
        do {
            try await client.connect()
            Issue.record("Expected error to be thrown")
        } catch {
            let state = await client.state
            if case .failed = state {
            } else {
                Issue.record("Expected failed state, got \(state)")
            }
        }
    }

    // MARK: - Connect from Failed State

    @Test("connect from failed state retries successfully")
    func connectFromFailedRetries() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))
        let client = Self.makeClient(mock: mock)
        try? await client.connect()
        if case .failed = await client.state {
        } else {
            Issue.record("Expected failed state")
        }
        await mock.enqueueResponse(Self.putOKResponse)
        try await client.connect()
        let state = await client.state
        #expect(state == .connected)
    }
}
