// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("SHOUTcast Protocol Handshake")
struct ShoutcastProtocolTests {

    let handler = ShoutcastProtocol()
    let credentials = IcecastCredentials.shoutcast(password: "hackme")
    let station = StationInfo(name: "Test Radio", genre: "Rock", isPublic: true, bitrate: 128)

    // MARK: - V1 Handshake Success

    @Test("V1 handshake succeeds with OK2")
    func v1Success() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\nicy-caps:11\r\n\r\n".utf8))

        let response = try await handler.performV1Handshake(
            connection: mock,
            credentials: credentials,
            contentType: .mp3,
            stationInfo: station
        )

        #expect(response.isOK)
    }

    @Test("V1 sends password line correctly")
    func v1PasswordSent() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        _ = try await handler.performV1Handshake(
            connection: mock,
            credentials: credentials,
            contentType: .mp3,
            stationInfo: station
        )

        let sentData = await mock.sentData
        let passwordLine = String(decoding: sentData[0], as: UTF8.self)
        #expect(passwordLine == "hackme\r\n")
    }

    @Test("V1 sends stream headers after OK2")
    func v1HeadersSent() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        _ = try await handler.performV1Handshake(
            connection: mock,
            credentials: credentials,
            contentType: .mp3,
            stationInfo: station
        )

        let sentData = await mock.sentData
        #expect(sentData.count == 2)
        let headers = String(decoding: sentData[1], as: UTF8.self)
        #expect(headers.contains("content-type: audio/mpeg"))
        #expect(headers.contains("icy-name: Test Radio"))
        #expect(headers.contains("icy-genre: Rock"))
        #expect(headers.contains("icy-pub: 1"))
        #expect(headers.contains("icy-br: 128"))
    }

    @Test("V1 OK2 with icy-caps parses capabilities")
    func v1WithCaps() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\nicy-caps:11\r\n\r\n".utf8))

        let response = try await handler.performV1Handshake(
            connection: mock,
            credentials: credentials,
            contentType: .mp3,
            stationInfo: station
        )

        #expect(response.capabilities == 11)
    }

    @Test("V1 OK2 without icy-caps still succeeds")
    func v1WithoutCaps() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        let response = try await handler.performV1Handshake(
            connection: mock,
            credentials: credentials,
            contentType: .mp3,
            stationInfo: station
        )

        #expect(response.isOK)
        #expect(response.capabilities == nil)
    }

    // MARK: - V1 Handshake Errors

    @Test("V1 non-OK2 response throws authenticationFailed")
    func v1NotOK2() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("INVALID\r\n".utf8))

        await #expect(throws: IcecastError.self) {
            try await handler.performV1Handshake(
                connection: mock,
                credentials: credentials,
                contentType: .mp3,
                stationInfo: station
            )
        }
    }

    @Test("V1 empty response throws error")
    func v1EmptyResponse() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data())

        await #expect(throws: IcecastError.self) {
            try await handler.performV1Handshake(
                connection: mock,
                credentials: credentials,
                contentType: .mp3,
                stationInfo: station
            )
        }
    }

    @Test("V1 connection lost after password throws error")
    func v1ConnectionLost() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.setReceiveError(.connectionLost(reason: "reset"))

        await #expect(throws: IcecastError.self) {
            try await handler.performV1Handshake(
                connection: mock,
                credentials: credentials,
                contentType: .mp3,
                stationInfo: station
            )
        }
    }

    // MARK: - V2 Handshake

    @Test("V2 sends password formatted as password:#streamId")
    func v2PasswordFormat() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        _ = try await handler.performV2Handshake(
            connection: mock,
            credentials: IcecastCredentials.shoutcast(password: "hackme"),
            streamId: 2,
            contentType: .mp3,
            stationInfo: station
        )

        let sentData = await mock.sentData
        let passwordLine = String(decoding: sentData[0], as: UTF8.self)
        #expect(passwordLine == "hackme:#2\r\n")
    }

    @Test("V2 with stream ID 1 sends correct password")
    func v2StreamId1() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        _ = try await handler.performV2Handshake(
            connection: mock,
            credentials: IcecastCredentials.shoutcast(password: "secret"),
            streamId: 1,
            contentType: .mp3,
            stationInfo: station
        )

        let sentData = await mock.sentData
        let passwordLine = String(decoding: sentData[0], as: UTF8.self)
        #expect(passwordLine == "secret:#1\r\n")
    }

    @Test("V2 sends stream headers after OK2")
    func v2HeadersSent() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("OK2\r\n".utf8))

        _ = try await handler.performV2Handshake(
            connection: mock,
            credentials: credentials,
            streamId: 1,
            contentType: .mp3,
            stationInfo: station
        )

        let sentData = await mock.sentData
        #expect(sentData.count == 2)
    }

    @Test("V2 authentication failure throws error")
    func v2AuthFailure() async throws {
        let mock = MockTransportConnection()
        try await mock.connect(host: "localhost", port: 8001, useTLS: false)
        await mock.enqueueResponse(Data("INVALID\r\n".utf8))

        await #expect(throws: IcecastError.self) {
            try await handler.performV2Handshake(
                connection: mock,
                credentials: credentials,
                streamId: 1,
                contentType: .mp3,
                stationInfo: station
            )
        }
    }

    // MARK: - Source Port Calculation

    @Test("Source port for listener 8000 is 8001")
    func sourcePort8000() {
        #expect(handler.sourcePort(forListenerPort: 8000) == 8001)
    }

    @Test("Source port for listener 80 is 81")
    func sourcePort80() {
        #expect(handler.sourcePort(forListenerPort: 80) == 81)
    }

    @Test("Source port for listener 0 is 1")
    func sourcePort0() {
        #expect(handler.sourcePort(forListenerPort: 0) == 1)
    }

    @Test("Source port for listener 65534 is 65535")
    func sourcePort65534() {
        #expect(handler.sourcePort(forListenerPort: 65534) == 65535)
    }
}
