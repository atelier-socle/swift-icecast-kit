// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Parses raw HTTP response bytes from Icecast and SHOUTcast servers.
///
/// Handles standard HTTP responses (status line + headers) and
/// SHOUTcast v1 authentication responses (OK2 + capabilities).
public struct HTTPResponseParser: Sendable {

    /// Creates a new HTTP response parser.
    public init() {}

    /// Parses a standard HTTP response from raw bytes.
    ///
    /// Extracts the protocol version, status code, status message,
    /// and headers. Also accepts `ICE/1.0` as a protocol version
    /// for legacy Icecast servers.
    ///
    /// - Parameter data: The raw response bytes.
    /// - Returns: A parsed ``HTTPResponse``.
    /// - Throws: ``IcecastError/emptyResponse`` or ``IcecastError/invalidResponse(reason:)``
    ///   if the response cannot be parsed.
    public func parse(_ data: Data) throws -> HTTPResponse {
        guard !data.isEmpty else {
            throw IcecastError.emptyResponse
        }

        guard let responseString = data.toUTF8String() ?? String(data: data, encoding: .ascii) else {
            throw IcecastError.invalidResponse(reason: "Response is not valid text")
        }

        let trimmed = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IcecastError.emptyResponse
        }

        // Split into lines (handle both \r\n and \n)
        let lines = responseString.components(separatedBy: "\r\n")

        guard let statusLine = lines.first, !statusLine.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw IcecastError.invalidResponse(reason: "Missing status line")
        }

        // Parse status line: "HTTP/1.1 200 OK" or "ICE/1.0 200 OK"
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)

        guard statusParts.count >= 2 else {
            throw IcecastError.invalidResponse(reason: "Malformed status line: \(statusLine)")
        }

        let protocolVersion = String(statusParts[0])

        guard protocolVersion.hasPrefix("HTTP/") || protocolVersion.hasPrefix("ICE/") else {
            throw IcecastError.invalidResponse(reason: "Unknown protocol: \(protocolVersion)")
        }

        guard let statusCode = Int(statusParts[1]) else {
            throw IcecastError.invalidResponse(reason: "Invalid status code: \(statusParts[1])")
        }

        let statusMessage = statusParts.count > 2 ? String(statusParts[2]) : ""

        // Parse headers
        var headers: [String: String] = [:]
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }

            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let value = String(line[line.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return HTTPResponse(
            statusCode: statusCode,
            statusMessage: statusMessage,
            protocolVersion: protocolVersion,
            headers: headers
        )
    }

    /// Parses a SHOUTcast v1 authentication response.
    ///
    /// SHOUTcast v1 responds with `"OK2"` on success, optionally followed
    /// by `"icy-caps:<value>"` indicating server capabilities.
    ///
    /// - Parameter data: The raw response bytes.
    /// - Returns: A parsed ``ShoutcastAuthResponse``.
    /// - Throws: ``IcecastError/emptyResponse`` if the response is empty.
    public func parseShoutcastAuth(_ data: Data) throws -> ShoutcastAuthResponse {
        guard !data.isEmpty else {
            throw IcecastError.emptyResponse
        }

        guard let responseString = data.toUTF8String() else {
            throw IcecastError.invalidResponse(reason: "SHOUTcast response is not valid UTF-8")
        }

        let trimmed = responseString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: "\r\n")

        let isOK = lines.first?.hasPrefix("OK2") ?? false

        var capabilities: Int?
        for line in lines {
            let lowered = line.lowercased()
            if lowered.hasPrefix("icy-caps:") {
                let valueString = String(line.dropFirst("icy-caps:".count))
                    .trimmingCharacters(in: .whitespaces)
                capabilities = Int(valueString)
            }
        }

        return ShoutcastAuthResponse(isOK: isOK, capabilities: capabilities)
    }
}

/// A parsed HTTP response from an Icecast or SHOUTcast server.
public struct HTTPResponse: Sendable, Hashable {

    /// The HTTP status code (e.g., 200, 401, 403).
    public var statusCode: Int

    /// The HTTP status message (e.g., "OK", "Unauthorized").
    public var statusMessage: String

    /// The protocol version (e.g., "HTTP/1.1", "ICE/1.0").
    public var protocolVersion: String

    /// The response headers, with keys lowercased.
    public var headers: [String: String]

    /// Creates a new HTTP response.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - statusMessage: The HTTP status message.
    ///   - protocolVersion: The protocol version string.
    ///   - headers: The response headers with lowercased keys.
    public init(
        statusCode: Int,
        statusMessage: String,
        protocolVersion: String,
        headers: [String: String]
    ) {
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.protocolVersion = protocolVersion
        self.headers = headers
    }
}

/// A parsed SHOUTcast v1 authentication response.
public struct ShoutcastAuthResponse: Sendable, Hashable {

    /// Whether the server accepted the authentication (`OK2` received).
    public var isOK: Bool

    /// The server capabilities bitmask, if provided via `icy-caps`.
    public var capabilities: Int?

    /// Creates a new SHOUTcast authentication response.
    ///
    /// - Parameters:
    ///   - isOK: Whether authentication succeeded.
    ///   - capabilities: The server capabilities value.
    public init(isOK: Bool, capabilities: Int?) {
        self.isOK = isOK
        self.capabilities = capabilities
    }
}
