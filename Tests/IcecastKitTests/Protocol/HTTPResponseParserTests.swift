// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation
import Testing

@testable import IcecastKit

@Suite("HTTP Response Parser")
struct HTTPResponseParserTests {

    let parser = HTTPResponseParser()

    // MARK: - Standard HTTP Responses

    @Test("Parses standard 200 OK response")
    func parse200OK() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 200)
        #expect(response.statusMessage == "OK")
        #expect(response.protocolVersion == "HTTP/1.1")
    }

    @Test("Parses 100 Continue response")
    func parse100Continue() throws {
        let raw = Data("HTTP/1.1 100 Continue\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 100)
        #expect(response.statusMessage == "Continue")
    }

    @Test("Parses 401 Unauthorized response")
    func parse401Unauthorized() throws {
        let raw = Data("HTTP/1.1 401 Unauthorized\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 401)
        #expect(response.statusMessage == "Unauthorized")
    }

    @Test("Parses 403 Forbidden response")
    func parse403Forbidden() throws {
        let raw = Data("HTTP/1.1 403 Mountpoint in use\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 403)
        #expect(response.statusMessage == "Mountpoint in use")
    }

    @Test("Parses 403 Content-type not supported")
    func parse403ContentType() throws {
        let raw = Data("HTTP/1.1 403 Content-type not supported\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 403)
        #expect(response.statusMessage == "Content-type not supported")
    }

    @Test("Parses 403 Too many sources")
    func parse403TooManySources() throws {
        let raw = Data("HTTP/1.1 403 Too many sources connected\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 403)
        #expect(response.statusMessage == "Too many sources connected")
    }

    @Test("Parses 500 Internal Server Error")
    func parse500ServerError() throws {
        let raw = Data("HTTP/1.1 500 Internal Server Error\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 500)
        #expect(response.statusMessage == "Internal Server Error")
    }

    @Test("Parses ICE/1.0 protocol version")
    func parseICEProtocol() throws {
        let raw = Data("ICE/1.0 200 OK\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 200)
        #expect(response.protocolVersion == "ICE/1.0")
    }

    // MARK: - Headers

    @Test("Parses headers with case-insensitive keys")
    func parseHeadersCaseInsensitive() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nServer: Icecast 2.4.4\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.headers["content-type"] == "audio/mpeg")
        #expect(response.headers["server"] == "Icecast 2.4.4")
    }

    @Test("Parses multiple headers")
    func parseMultipleHeaders() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nA: 1\r\nB: 2\r\nC: 3\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.headers.count == 3)
        #expect(response.headers["a"] == "1")
        #expect(response.headers["b"] == "2")
        #expect(response.headers["c"] == "3")
    }

    @Test("Parses header with extra whitespace")
    func parseHeaderExtraWhitespace() throws {
        let raw = Data("HTTP/1.1 200 OK\r\n  Content-Type :  audio/mpeg  \r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.headers["content-type"] == "audio/mpeg")
    }

    @Test("Parses header with colon in value")
    func parseHeaderColonInValue() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nice-url: https://example.com:8000\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.headers["ice-url"] == "https://example.com:8000")
    }

    @Test("Handles very long header values")
    func parseLongHeaderValues() throws {
        let longValue = String(repeating: "x", count: 4096)
        let raw = Data("HTTP/1.1 200 OK\r\nX-Long: \(longValue)\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.headers["x-long"] == longValue)
    }

    // MARK: - Error Cases

    @Test("Empty response throws emptyResponse error")
    func emptyResponseThrows() {
        #expect(throws: IcecastError.self) {
            try parser.parse(Data())
        }
    }

    @Test("Whitespace-only response throws emptyResponse error")
    func whitespaceOnlyResponseThrows() {
        let raw = Data("   \r\n  \r\n".utf8)
        #expect(throws: IcecastError.self) {
            try parser.parse(raw)
        }
    }

    @Test("Truncated status line throws invalidResponse error")
    func truncatedStatusLineThrows() {
        let raw = Data("HTTP".utf8)
        #expect(throws: IcecastError.self) {
            try parser.parse(raw)
        }
    }

    @Test("Garbage bytes throw invalidResponse error")
    func garbageBytesThrow() {
        let raw = Data([0xFF, 0xFE, 0xFD, 0xFC, 0x00, 0x01])
        #expect(throws: IcecastError.self) {
            try parser.parse(raw)
        }
    }

    @Test("Status code without message parses successfully")
    func statusCodeWithoutMessage() throws {
        let raw = Data("HTTP/1.1 200\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 200)
        #expect(response.statusMessage == "")
    }

    @Test("Unknown protocol throws invalidResponse error")
    func unknownProtocolThrows() {
        let raw = Data("FTP/1.0 200 OK\r\n\r\n".utf8)
        #expect(throws: IcecastError.self) {
            try parser.parse(raw)
        }
    }

    @Test("Invalid status code throws invalidResponse error")
    func invalidStatusCodeThrows() {
        let raw = Data("HTTP/1.1 abc OK\r\n\r\n".utf8)
        #expect(throws: IcecastError.self) {
            try parser.parse(raw)
        }
    }

    @Test("Response with no headers")
    func responseNoHeaders() throws {
        let raw = Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.headers.isEmpty)
    }

    @Test("Partial response with headers not complete")
    func partialResponse() throws {
        let raw = Data("HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg".utf8)
        let response = try parser.parse(raw)
        #expect(response.statusCode == 200)
        #expect(response.headers["content-type"] == "audio/mpeg")
    }

    // MARK: - SHOUTcast Auth

    @Test("SHOUTcast OK2 response is parsed correctly")
    func shoutcastOK2() throws {
        let raw = Data("OK2\r\nicy-caps:11\r\n\r\n".utf8)
        let response = try parser.parseShoutcastAuth(raw)
        #expect(response.isOK)
        #expect(response.capabilities == 11)
    }

    @Test("SHOUTcast OK2 without icy-caps")
    func shoutcastOK2NoCaps() throws {
        let raw = Data("OK2\r\n".utf8)
        let response = try parser.parseShoutcastAuth(raw)
        #expect(response.isOK)
        #expect(response.capabilities == nil)
    }

    @Test("SHOUTcast invalid response is not OK")
    func shoutcastInvalidNotOK() throws {
        let raw = Data("INVALID\r\n".utf8)
        let response = try parser.parseShoutcastAuth(raw)
        #expect(!response.isOK)
    }

    @Test("SHOUTcast empty response throws emptyResponse error")
    func shoutcastEmptyThrows() {
        #expect(throws: IcecastError.self) {
            try parser.parseShoutcastAuth(Data())
        }
    }

    @Test("SHOUTcast OK2 with zero capabilities")
    func shoutcastOK2ZeroCaps() throws {
        let raw = Data("OK2\r\nicy-caps:0\r\n\r\n".utf8)
        let response = try parser.parseShoutcastAuth(raw)
        #expect(response.isOK)
        #expect(response.capabilities == 0)
    }

    @Test("HTTP/1.0 protocol version is accepted")
    func httpOneZero() throws {
        let raw = Data("HTTP/1.0 200 OK\r\n\r\n".utf8)
        let response = try parser.parse(raw)
        #expect(response.protocolVersion == "HTTP/1.0")
        #expect(response.statusCode == 200)
    }
}
