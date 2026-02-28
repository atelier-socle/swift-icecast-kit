// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Protocol Negotiator")
struct ProtocolNegotiatorTests {

    let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
    let credentials = IcecastCredentials(password: "hackme")

    // MARK: - Auto Mode

    @Test("Auto mode returns icecastPUT when PUT succeeds")
    func autoPUTSucceeds() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        #expect(mode == .icecastPUT)
    }

    @Test("Auto mode falls back to SOURCE on empty PUT response")
    func autoFallbackToSOURCE() async throws {
        let primaryMock = MockTransportConnection()
        try await primaryMock.connect(host: "localhost", port: 8000, useTLS: false)
        await primaryMock.enqueueResponse(Data())

        let fallbackMock = MockTransportConnection()
        await fallbackMock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { fallbackMock }
        let mode = try await negotiator.negotiate(
            connection: primaryMock,
            configuration: config,
            credentials: credentials
        )

        #expect(mode == .icecastSOURCE)
    }

    @Test("Auto mode closes original connection on fallback")
    func autoClosesOriginal() async throws {
        let primaryMock = MockTransportConnection()
        try await primaryMock.connect(host: "localhost", port: 8000, useTLS: false)
        await primaryMock.enqueueResponse(Data())

        let fallbackMock = MockTransportConnection()
        await fallbackMock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { fallbackMock }
        _ = try await negotiator.negotiate(
            connection: primaryMock,
            configuration: config,
            credentials: credentials
        )

        let primaryClosed = await primaryMock.closeCallCount
        #expect(primaryClosed == 1)
    }

    @Test("Auto mode sets fallbackConnection on SOURCE fallback")
    func autoSetsFallbackConnection() async throws {
        let primaryMock = MockTransportConnection()
        try await primaryMock.connect(host: "localhost", port: 8000, useTLS: false)
        await primaryMock.enqueueResponse(Data())

        let fallbackMock = MockTransportConnection()
        await fallbackMock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { fallbackMock }
        _ = try await negotiator.negotiate(
            connection: primaryMock,
            configuration: config,
            credentials: credentials
        )

        let fallback = await negotiator.fallbackConnection
        #expect(fallback != nil)
    }

    @Test("Auto mode fallbackConnection is nil when PUT succeeds")
    func autoNoFallbackOnSuccess() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        _ = try await negotiator.negotiate(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let fallback = await negotiator.fallbackConnection
        #expect(fallback == nil)
    }

    @Test("Auto mode throws protocolNegotiationFailed when both fail")
    func autoBothFail() async throws {
        let primaryMock = MockTransportConnection()
        try await primaryMock.connect(host: "localhost", port: 8000, useTLS: false)
        await primaryMock.enqueueResponse(Data())

        let fallbackMock = MockTransportConnection()
        await fallbackMock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { fallbackMock }

        do {
            _ = try await negotiator.negotiate(
                connection: primaryMock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .protocolNegotiationFailed(let tried) = error {
                #expect(tried == ["PUT", "SOURCE"])
            } else {
                Issue.record("Expected protocolNegotiationFailed, got \(error)")
            }
        }
    }

    @Test("Auto mode propagates auth error without fallback")
    func autoAuthErrorNoFallback() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { MockTransportConnection() }

        await #expect(throws: IcecastError.self) {
            try await negotiator.negotiate(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
        }
    }

    @Test("Auto mode propagates mountpointInUse without fallback")
    func autoMountpointInUseNoFallback() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 Mountpoint in use\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { MockTransportConnection() }

        do {
            _ = try await negotiator.negotiate(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .mountpointInUse = error {
                // Expected — propagated directly, no fallback
            } else {
                Issue.record("Expected mountpointInUse, got \(error)")
            }
        }
    }

    @Test("Auto mode fallback connects to same host and port")
    func autoFallbackConnectsCorrectly() async throws {
        let primaryMock = MockTransportConnection()
        try await primaryMock.connect(host: "localhost", port: 8000, useTLS: false)
        await primaryMock.enqueueResponse(Data())

        let fallbackMock = MockTransportConnection()
        await fallbackMock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { fallbackMock }
        _ = try await negotiator.negotiate(
            connection: primaryMock,
            configuration: config,
            credentials: credentials
        )

        let host = await fallbackMock.lastConnectHost
        let port = await fallbackMock.lastConnectPort
        #expect(host == "localhost")
        #expect(port == 8000)
    }

    // MARK: - Direct Modes

    @Test("icecastPUT mode only tries PUT")
    func directPUT() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        var putConfig = config
        putConfig.protocolMode = .icecastPUT

        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: putConfig,
            credentials: credentials
        )

        #expect(mode == .icecastPUT)
    }

    @Test("icecastSOURCE mode only tries SOURCE")
    func directSOURCE() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        var sourceConfig = config
        sourceConfig.protocolMode = .icecastSOURCE

        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: sourceConfig,
            credentials: credentials
        )

        #expect(mode == .icecastSOURCE)
    }

    @Test("shoutcastV1 mode performs v1 handshake")
    func directShoutcastV1() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\nicy-caps:11\r\n\r\n".utf8))

        var scConfig = config
        scConfig.protocolMode = .shoutcastV1

        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: scConfig,
            credentials: credentials
        )

        #expect(mode == .shoutcastV1)
    }

    @Test("shoutcastV2 mode performs v2 handshake with stream ID")
    func directShoutcastV2() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        var scConfig = config
        scConfig.protocolMode = .shoutcastV2(streamId: 2)

        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        let mode = try await negotiator.negotiate(
            connection: mock,
            configuration: scConfig,
            credentials: credentials
        )

        #expect(mode == .shoutcastV2(streamId: 2))
    }

    @Test("shoutcastV1 sends correct password line")
    func shoutcastV1PasswordLine() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        var scConfig = config
        scConfig.protocolMode = .shoutcastV1

        let scCreds = IcecastCredentials.shoutcast(password: "mypass")
        let negotiator = ProtocolNegotiator { MockTransportConnection() }
        _ = try await negotiator.negotiate(
            connection: mock,
            configuration: scConfig,
            credentials: scCreds
        )

        let sentData = await mock.sentData
        let passwordLine = String(decoding: sentData[0], as: UTF8.self)
        #expect(passwordLine == "mypass\r\n")
    }

    // MARK: - Error Propagation

    @Test("Auth errors pass through from direct PUT mode")
    func directPUTAuthError() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))

        var putConfig = config
        putConfig.protocolMode = .icecastPUT

        let negotiator = ProtocolNegotiator { MockTransportConnection() }

        await #expect(throws: IcecastError.self) {
            try await negotiator.negotiate(
                connection: mock,
                configuration: putConfig,
                credentials: credentials
            )
        }
    }

    @Test("Connection errors pass through")
    func connectionErrorPassthrough() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.setReceiveError(.connectionLost(reason: "reset"))

        let negotiator = ProtocolNegotiator { MockTransportConnection() }

        await #expect(throws: IcecastError.self) {
            try await negotiator.negotiate(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
        }
    }

    @Test("Direct SOURCE error does not attempt PUT")
    func directSOURCEError() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))

        var sourceConfig = config
        sourceConfig.protocolMode = .icecastSOURCE

        let negotiator = ProtocolNegotiator { MockTransportConnection() }

        await #expect(throws: IcecastError.self) {
            try await negotiator.negotiate(
                connection: mock,
                configuration: sourceConfig,
                credentials: credentials
            )
        }

        let sendCount = await mock.sendCallCount
        #expect(sendCount == 1)
    }

    // MARK: - Concurrency

    @Test("Negotiator is actor-isolated (concurrent access safe)")
    func concurrencySafe() async throws {
        let mock1 = MockTransportConnection()
        try await mock1.connect(host: "localhost", port: 8000, useTLS: false)
        await mock1.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let mock2 = MockTransportConnection()
        try await mock2.connect(host: "localhost", port: 8000, useTLS: false)
        await mock2.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let negotiator = ProtocolNegotiator { MockTransportConnection() }

        let mode1 = try await negotiator.negotiate(
            connection: mock1,
            configuration: config,
            credentials: credentials
        )

        let mode2 = try await negotiator.negotiate(
            connection: mock2,
            configuration: config,
            credentials: credentials
        )

        #expect(mode1 == .icecastPUT)
        #expect(mode2 == .icecastPUT)
    }

    @Test("Auto mode closes fallback connection on SOURCE failure")
    func autoClosesFallbackOnFailure() async throws {
        let primaryMock = MockTransportConnection()
        try await primaryMock.connect(host: "localhost", port: 8000, useTLS: false)
        await primaryMock.enqueueResponse(Data())

        let fallbackMock = MockTransportConnection()
        await fallbackMock.enqueueResponse(Data())

        let negotiator = ProtocolNegotiator { fallbackMock }

        do {
            _ = try await negotiator.negotiate(
                connection: primaryMock,
                configuration: config,
                credentials: credentials
            )
        } catch {
            // Expected
        }

        let fallbackClosed = await fallbackMock.closeCallCount
        #expect(fallbackClosed == 1)
    }
}
