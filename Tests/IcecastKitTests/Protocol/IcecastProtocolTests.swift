// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("Icecast Protocol Handshake")
struct IcecastProtocolTests {

    let handler = IcecastProtocol()
    let config = IcecastConfiguration(host: "localhost", mountpoint: "/live.mp3")
    let credentials = IcecastCredentials(password: "hackme")

    // MARK: - PUT Success

    @Test("PUT handshake succeeds with 200 OK directly")
    func putSuccess200() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let sendCount = await mock.sendCallCount
        #expect(sendCount == 1)
    }

    @Test("PUT handshake succeeds with 100 Continue then 200 OK")
    func putSuccess100Then200() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponses([
            Data("HTTP/1.1 100 Continue\r\n\r\n".utf8),
            Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        ])

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let receiveCount = await mock.receiveCallCount
        #expect(receiveCount == 2)
    }

    @Test("PUT request contains correct method and path")
    func putRequestMethod() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.hasPrefix("PUT /live.mp3 HTTP/1.1\r\n"))
    }

    @Test("PUT request contains Authorization header")
    func putAuthorizationHeader() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Authorization: Basic"))
    }

    @Test("PUT request contains correct Content-Type")
    func putContentType() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Content-Type: audio/mpeg"))
    }

    @Test("PUT request contains ice-* headers")
    func putIceHeaders() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let stationConfig = IcecastConfiguration(
            host: "localhost",
            mountpoint: "/live.mp3",
            stationInfo: StationInfo(name: "Test Radio", isPublic: true)
        )

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: stationConfig,
            credentials: credentials
        )

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("ice-name: Test Radio"))
        #expect(request.contains("ice-public: 1"))
    }

    // MARK: - PUT Errors

    @Test("PUT 401 throws authenticationFailed")
    func put401() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))

        await #expect(throws: IcecastError.self) {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
        }
    }

    @Test("PUT 403 Mountpoint in use throws mountpointInUse")
    func put403MountpointInUse() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 Mountpoint in use\r\n\r\n".utf8))

        do {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .mountpointInUse(let mount) = error {
                #expect(mount == "/live.mp3")
            } else {
                Issue.record("Expected mountpointInUse, got \(error)")
            }
        }
    }

    @Test("PUT 403 Content-type not supported throws contentTypeNotSupported")
    func put403ContentType() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 Content-type not supported\r\n\r\n".utf8))

        do {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .contentTypeNotSupported = error {
                // Expected
            } else {
                Issue.record("Expected contentTypeNotSupported, got \(error)")
            }
        }
    }

    @Test("PUT 403 Too many sources throws tooManySources")
    func put403TooManySources() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 Too many sources connected\r\n\r\n".utf8))

        do {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .tooManySources = error {
                // Expected
            } else {
                Issue.record("Expected tooManySources, got \(error)")
            }
        }
    }

    @Test("PUT 403 unknown message throws unexpectedResponse")
    func put403Unknown() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 Some unknown error\r\n\r\n".utf8))

        do {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .unexpectedResponse(let code, _) = error {
                #expect(code == 403)
            } else {
                Issue.record("Expected unexpectedResponse, got \(error)")
            }
        }
    }

    @Test("PUT 500 throws serverError")
    func put500() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 500 Internal Server Error\r\n\r\n".utf8))

        do {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .serverError(let code, _) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected serverError, got \(error)")
            }
        }
    }

    @Test("PUT empty response throws emptyResponse")
    func putEmptyResponse() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data())

        await #expect(throws: IcecastError.emptyResponse) {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
        }
    }

    // MARK: - SOURCE Success

    @Test("SOURCE handshake succeeds with 200 OK")
    func sourceSuccess200() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        try await handler.performSOURCEHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let sendCount = await mock.sendCallCount
        #expect(sendCount == 1)
    }

    @Test("SOURCE handshake succeeds with ICE/1.0 200 OK")
    func sourceSuccessICE() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("ICE/1.0 200 OK\r\n\r\n".utf8))

        try await handler.performSOURCEHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )
    }

    @Test("SOURCE request contains correct method and protocol")
    func sourceRequestMethod() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        try await handler.performSOURCEHandshake(
            connection: mock,
            configuration: config,
            credentials: credentials
        )

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.hasPrefix("SOURCE /live.mp3 ICE/1.0\r\n"))
    }

    // MARK: - SOURCE Errors

    @Test("SOURCE 401 throws authenticationFailed")
    func source401() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8))

        await #expect(throws: IcecastError.self) {
            try await handler.performSOURCEHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
        }
    }

    @Test("SOURCE 403 maps to appropriate error")
    func source403() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 Mountpoint in use\r\n\r\n".utf8))

        do {
            try await handler.performSOURCEHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .mountpointInUse = error {
                // Expected
            } else {
                Issue.record("Expected mountpointInUse, got \(error)")
            }
        }
    }

    @Test("SOURCE empty response throws emptyResponse")
    func sourceEmptyResponse() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data())

        await #expect(throws: IcecastError.emptyResponse) {
            try await handler.performSOURCEHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
        }
    }

    @Test("PUT 403 No Content-type given throws contentTypeNotSupported")
    func put403NoContentType() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 403 No Content-type given\r\n\r\n".utf8))

        do {
            try await handler.performPUTHandshake(
                connection: mock,
                configuration: config,
                credentials: credentials
            )
            Issue.record("Expected error")
        } catch let error as IcecastError {
            if case .contentTypeNotSupported = error {
                // Expected
            } else {
                Issue.record("Expected contentTypeNotSupported, got \(error)")
            }
        }
    }

    @Test("PUT request with AAC content type sends correct header")
    func putAACContentType() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8000, useTLS: false)
        await mock.enqueueResponse(Data("HTTP/1.1 200 OK\r\n\r\n".utf8))

        let aacConfig = IcecastConfiguration(
            host: "localhost",
            mountpoint: "/live.aac",
            contentType: .aac
        )

        try await handler.performPUTHandshake(
            connection: mock,
            configuration: aacConfig,
            credentials: credentials
        )

        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Content-Type: audio/aac"))
    }
}
