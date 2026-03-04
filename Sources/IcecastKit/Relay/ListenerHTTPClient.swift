// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Parsed URL components for an Icecast stream connection.
struct ParsedStreamURL: Sendable {
    let host: String
    let port: Int
    let mountpoint: String
    let useTLS: Bool
}

/// Parsed response headers from an Icecast listener connection.
struct ListenerResponseHeaders: Sendable {
    /// HTTP status code (e.g. 200).
    let statusCode: Int
    /// Content type from the `content-type` header.
    let contentType: String?
    /// Metadata interval from the `icy-metaint` header.
    let icyMetaint: Int?
    /// Station name from the `icy-name` header.
    let icyName: String?
    /// Genre from the `icy-genre` header.
    let icyGenre: String?
    /// Bitrate from the `icy-br` header.
    let icyBitrate: Int?
    /// Server version from `Server` or `icy-version` header.
    let serverVersion: String?
}

/// Internal HTTP GET client for connecting to an Icecast stream as a listener.
///
/// Handles ICY protocol negotiation and header parsing. Uses the same
/// transport layer as ``IcecastClient`` for cross-platform compatibility.
actor ListenerHTTPClient {

    private let configuration: IcecastRelayConfiguration
    private let transportFactory: @Sendable () -> any TransportConnection
    private var connection: (any TransportConnection)?

    /// Creates a listener HTTP client.
    ///
    /// - Parameters:
    ///   - configuration: The relay configuration with URL and options.
    ///   - transportFactory: Factory for creating transport connections.
    init(
        configuration: IcecastRelayConfiguration,
        transportFactory: @Sendable @escaping () -> any TransportConnection
    ) {
        self.configuration = configuration
        self.transportFactory = transportFactory
    }

    /// Connects to the stream URL and returns parsed response headers.
    ///
    /// - Returns: Parsed response headers.
    /// - Throws: ``IcecastError/relayConnectionFailed(url:reason:)`` on failure.
    func connect() async throws -> ListenerResponseHeaders {
        let parsed = try parseURL(configuration.sourceURL)
        let host = parsed.host
        let port = parsed.port
        let mountpoint = parsed.mountpoint
        let useTLS = parsed.useTLS

        let transport = transportFactory()
        connection = transport

        do {
            try await transport.connect(host: host, port: port, useTLS: useTLS)
        } catch {
            throw IcecastError.relayConnectionFailed(
                url: configuration.sourceURL,
                reason: "Connection failed: \(error)"
            )
        }

        let request = buildGetRequest(
            mountpoint: mountpoint,
            host: host,
            port: port
        )
        do {
            try await transport.send(request)
        } catch {
            throw IcecastError.relayConnectionFailed(
                url: configuration.sourceURL,
                reason: "Failed to send request: \(error)"
            )
        }

        let responseData: Data
        do {
            responseData = try await transport.receive(
                maxBytes: 8192,
                timeout: configuration.connectionTimeout
            )
        } catch {
            throw IcecastError.relayConnectionFailed(
                url: configuration.sourceURL,
                reason: "No response from server: \(error)"
            )
        }

        return try parseResponse(responseData)
    }

    /// Reads the next chunk of raw bytes from the stream.
    ///
    /// - Parameter size: Maximum number of bytes to read.
    /// - Returns: Data received, or `nil` when the stream ends cleanly.
    func readChunk(size: Int) async throws -> Data? {
        guard let transport = connection else { return nil }

        let isStillConnected = await transport.isConnected
        guard isStillConnected else { return nil }

        do {
            let data = try await transport.receive(maxBytes: size)
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }

    /// Disconnects cleanly.
    func disconnect() async {
        if let transport = connection {
            await transport.close()
        }
        connection = nil
    }

    // MARK: - Private

    /// Parses a URL string into host, port, mountpoint, and TLS flag.
    private func parseURL(_ urlString: String) throws -> ParsedStreamURL {
        guard let components = URLComponents(string: urlString) else {
            throw IcecastError.relayConnectionFailed(
                url: urlString, reason: "Invalid URL"
            )
        }

        let scheme = components.scheme?.lowercased() ?? "http"
        let useTLS = scheme == "https"
        let defaultPort = useTLS ? 443 : 8000

        guard let host = components.host, !host.isEmpty else {
            throw IcecastError.relayConnectionFailed(
                url: urlString, reason: "Missing host"
            )
        }

        let port = components.port ?? defaultPort
        let mountpoint = components.path.isEmpty ? "/" : components.path

        return ParsedStreamURL(
            host: host, port: port,
            mountpoint: mountpoint, useTLS: useTLS
        )
    }

    /// Builds an HTTP GET request for an Icecast listener connection.
    private func buildGetRequest(
        mountpoint: String,
        host: String,
        port: Int
    ) -> Data {
        var request = "GET \(mountpoint) HTTP/1.0\r\n"
        request += "Host: \(host):\(port)\r\n"
        request += "User-Agent: \(configuration.userAgent)\r\n"
        request += "Accept: */*\r\n"

        if configuration.requestICYMetadata {
            request += "Icy-MetaData: 1\r\n"
        }

        if let creds = configuration.credentials {
            request += "Authorization: Basic \(creds.basicAuthHeaderValue())\r\n"
        }

        request += "Connection: close\r\n"
        request += "\r\n"

        return Data(request.utf8)
    }

    /// Parses an HTTP response (status line + headers) and any trailing audio data.
    private func parseResponse(_ data: Data) throws -> ListenerResponseHeaders {
        let responseString = String(decoding: data, as: UTF8.self)

        guard let headerEnd = responseString.range(of: "\r\n\r\n") else {
            throw IcecastError.relayConnectionFailed(
                url: configuration.sourceURL,
                reason: "Incomplete HTTP response"
            )
        }

        let headerSection = String(responseString[..<headerEnd.lowerBound])
        let lines = headerSection.components(separatedBy: "\r\n")

        guard let statusLine = lines.first else {
            throw IcecastError.relayConnectionFailed(
                url: configuration.sourceURL,
                reason: "Missing status line"
            )
        }

        let statusCode = parseStatusCode(statusLine)

        guard statusCode == 200 else {
            if statusCode == 401 {
                throw IcecastError.authenticationFailed(
                    statusCode: 401,
                    message: "Relay source requires authentication"
                )
            }
            throw IcecastError.relayConnectionFailed(
                url: configuration.sourceURL,
                reason: "HTTP \(statusCode)"
            )
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let value = String(line[line.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return ListenerResponseHeaders(
            statusCode: statusCode,
            contentType: headers["content-type"],
            icyMetaint: headers["icy-metaint"].flatMap { Int($0) },
            icyName: headers["icy-name"],
            icyGenre: headers["icy-genre"],
            icyBitrate: headers["icy-br"].flatMap { Int($0) },
            serverVersion: headers["server"] ?? headers["icy-version"]
        )
    }

    /// Extracts the HTTP status code from the status line.
    private func parseStatusCode(_ line: String) -> Int {
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let code = Int(parts[1]) else {
            return 0
        }
        return code
    }
}
