// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

// MARK: - ListenerHTTPClient Tests

@Suite("ListenerHTTPClient")
struct ListenerHTTPClientTests {

    /// Builds a mock HTTP response with optional ICY headers.
    private func buildResponse(
        statusCode: Int = 200,
        contentType: String? = "audio/mpeg",
        metaint: Int? = 8192,
        name: String? = nil,
        genre: String? = nil,
        bitrate: Int? = nil,
        server: String? = nil
    ) -> Data {
        var response = "HTTP/1.0 \(statusCode) OK\r\n"
        if let ct = contentType {
            response += "content-type: \(ct)\r\n"
        }
        if let mi = metaint {
            response += "icy-metaint: \(mi)\r\n"
        }
        if let n = name {
            response += "icy-name: \(n)\r\n"
        }
        if let g = genre {
            response += "icy-genre: \(g)\r\n"
        }
        if let b = bitrate {
            response += "icy-br: \(b)\r\n"
        }
        if let s = server {
            response += "Server: \(s)\r\n"
        }
        response += "\r\n"
        return Data(response.utf8)
    }

    @Test("successful connection parses headers correctly")
    func successfulConnection() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            buildResponse(
                contentType: "audio/mpeg",
                metaint: 16000,
                name: "Test Radio",
                genre: "Rock",
                bitrate: 128,
                server: "Icecast 2.4.4"
            ))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        let headers = try await client.connect()
        #expect(headers.statusCode == 200)
        #expect(headers.contentType == "audio/mpeg")
        #expect(headers.icyMetaint == 16000)
        #expect(headers.icyName == "Test Radio")
        #expect(headers.icyGenre == "Rock")
        #expect(headers.icyBitrate == 128)
        #expect(headers.serverVersion == "Icecast 2.4.4")
    }

    @Test("icy-metaint extracted correctly")
    func icyMetaintExtracted() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(buildResponse(metaint: 32768))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        let headers = try await client.connect()
        #expect(headers.icyMetaint == 32768)
    }

    @Test("content-type audio/mpeg detected")
    func contentTypeMpeg() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(buildResponse(contentType: "audio/mpeg"))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        let headers = try await client.connect()
        #expect(headers.contentType == "audio/mpeg")
    }

    @Test("content-type audio/aac detected")
    func contentTypeAac() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(buildResponse(contentType: "audio/aac"))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.aac"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        let headers = try await client.connect()
        #expect(headers.contentType == "audio/aac")
    }

    @Test("content-type application/ogg detected")
    func contentTypeOgg() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            buildResponse(contentType: "application/ogg")
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.ogg"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        let headers = try await client.connect()
        #expect(headers.contentType == "application/ogg")
    }

    @Test("HTTP 401 throws authenticationFailed")
    func http401() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 401 Unauthorized\r\n\r\n".utf8)
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("HTTP 404 throws relayConnectionFailed")
    func http404() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("HTTP/1.0 404 Not Found\r\n\r\n".utf8)
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/nonexistent"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("connection failure throws relayConnectionFailed")
    func connectionFailure() async throws {
        let mock = MockTransportConnection()
        await mock.setConnectError(
            .connectionFailed(host: "bad", port: 0, reason: "test")
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://bad:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("readChunk returns data then nil on stream end")
    func readChunkThenEnd() async throws {
        let mock = MockTransportConnection()
        let audioData = Data(repeating: 0xFF, count: 100)
        await mock.enqueueResponse(buildResponse())
        await mock.enqueueResponse(audioData)

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        _ = try await client.connect()
        let chunk = try await client.readChunk(size: 65536)
        #expect(chunk == audioData)

        let end = try await client.readChunk(size: 65536)
        #expect(end == nil)
    }

    @Test("disconnect closes transport")
    func disconnectCloses() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(buildResponse())

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        _ = try await client.connect()
        await client.disconnect()

        let closeCount = await mock.closeCallCount
        #expect(closeCount >= 1)
    }

    @Test("invalid URL throws relayConnectionFailed")
    func invalidURL() async throws {
        let config = IcecastRelayConfiguration(sourceURL: "://invalid")
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { MockTransportConnection() }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("HTTPS URL sets TLS flag")
    func httpsSetsTLS() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(buildResponse())

        let config = IcecastRelayConfiguration(
            sourceURL: "https://secure.example.com:443/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        _ = try await client.connect()
        let usedTLS = await mock.lastConnectUseTLS
        #expect(usedTLS == true)
    }

    @Test("send failure throws relayConnectionFailed")
    func sendFailure() async throws {
        let mock = MockTransportConnection()
        await mock.setSendError(
            .connectionLost(reason: "broken pipe")
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("incomplete HTTP response throws relayConnectionFailed")
    func incompleteResponse() async throws {
        let mock = MockTransportConnection()
        // Response without \r\n\r\n terminator
        await mock.enqueueResponse(
            Data("HTTP/1.0 200 OK\r\ncontent-type: audio/mpeg".utf8)
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("empty response body throws relayConnectionFailed")
    func emptyResponse() async throws {
        let mock = MockTransportConnection()
        // Just the header separator, no status line
        await mock.enqueueResponse(Data("\r\n\r\n".utf8))

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("credentials included in request when configured")
    func credentialsInRequest() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(buildResponse())

        let creds = IcecastCredentials(password: "secret")
        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3",
            credentials: creds
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        _ = try await client.connect()
        let sentData = await mock.sentData
        let request = String(decoding: sentData[0], as: UTF8.self)
        #expect(request.contains("Authorization: Basic"))
    }

    @Test("malformed status line returns status code 0")
    func malformedStatusLine() async throws {
        let mock = MockTransportConnection()
        await mock.enqueueResponse(
            Data("INVALID_STATUS_LINE\r\n\r\n".utf8)
        )

        let config = IcecastRelayConfiguration(
            sourceURL: "http://localhost:8000/live.mp3"
        )
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { mock }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }

    @Test("URL with empty host throws relayConnectionFailed")
    func emptyHost() async throws {
        let config = IcecastRelayConfiguration(sourceURL: "http:///live.mp3")
        let client = ListenerHTTPClient(
            configuration: config,
            transportFactory: { MockTransportConnection() }
        )

        await #expect(throws: IcecastError.self) {
            _ = try await client.connect()
        }
    }
}
