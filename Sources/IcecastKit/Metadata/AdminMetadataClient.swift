// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Client for the Icecast admin HTTP API.
///
/// Supports metadata updates via `/admin/metadata` and server stats via `/admin/stats`.
/// Uses a separate TCP connection from the source stream connection.
/// Requires admin credentials (may differ from source credentials).
public actor AdminMetadataClient {

    private let host: String
    private let port: Int
    private let useTLS: Bool
    private let credentials: IcecastCredentials
    private let connectionFactory: @Sendable () -> any TransportConnection

    /// Maximum response size for admin API requests.
    static let maxResponseSize = 65536

    /// Creates a new admin metadata client.
    ///
    /// - Parameters:
    ///   - host: The server hostname.
    ///   - port: The server port.
    ///   - useTLS: Whether to use TLS.
    ///   - credentials: The admin authentication credentials.
    ///   - connectionFactory: A factory for creating transport connections.
    ///     Defaults to ``TransportConnectionFactory/makeConnection()``.
    public init(
        host: String,
        port: Int,
        useTLS: Bool,
        credentials: IcecastCredentials,
        connectionFactory: @Sendable @escaping () -> any TransportConnection =
            TransportConnectionFactory.makeConnection
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.credentials = credentials
        self.connectionFactory = connectionFactory
    }

    /// Updates stream metadata via the admin API.
    ///
    /// Sends a `GET /admin/metadata?mount=...&mode=updinfo&song=...` request.
    ///
    /// - Parameters:
    ///   - metadata: The metadata to update.
    ///   - mountpoint: The mountpoint path to update metadata for.
    /// - Throws: ``IcecastError`` on failure.
    public func updateMetadata(_ metadata: ICYMetadata, mountpoint: String) async throws {
        guard let song = metadata.urlEncodedSong() else {
            throw IcecastError.metadataUpdateFailed(reason: "No stream title to update")
        }

        let path = "/admin/metadata?mount=\(mountpoint)&mode=updinfo&song=\(song)"
        let response = try await sendAdminRequest(path: path)

        try handleResponseStatus(response)
    }

    /// Fetches global server statistics.
    ///
    /// Sends a `GET /admin/stats` request and parses the XML response.
    ///
    /// - Returns: The parsed server statistics.
    /// - Throws: ``IcecastError`` on failure.
    public func fetchServerStats() async throws -> ServerStats {
        let (response, body) = try await sendAdminRequestWithBody(path: "/admin/stats")
        try handleResponseStatus(response)

        let parser = IcecastXMLParser()
        return try parser.parseServerStats(from: body)
    }

    /// Fetches statistics for a specific mountpoint.
    ///
    /// Sends a `GET /admin/stats?mount=...` request and parses the XML response.
    ///
    /// - Parameter mountpoint: The mountpoint to fetch stats for.
    /// - Returns: The parsed mountpoint statistics.
    /// - Throws: ``IcecastError`` on failure.
    public func fetchMountStats(mountpoint: String) async throws -> MountStats {
        let path = "/admin/stats?mount=\(mountpoint)"
        let (response, body) = try await sendAdminRequestWithBody(path: path)
        try handleResponseStatus(response)

        let parser = IcecastXMLParser()
        return try parser.parseMountStats(from: body, mountpoint: mountpoint)
    }

    // MARK: - Private

    /// Sends an admin API GET request and returns the parsed HTTP response.
    private func sendAdminRequest(path: String) async throws -> HTTPResponse {
        let (response, _) = try await sendAdminRequestWithBody(path: path)
        return response
    }

    /// Sends an admin API GET request and returns both the parsed response and raw body.
    private func sendAdminRequestWithBody(
        path: String
    ) async throws -> (HTTPResponse, Data) {
        let connection = connectionFactory()

        do {
            try await connection.connect(host: host, port: port, useTLS: useTLS)
        } catch {
            throw IcecastError.connectionFailed(host: host, port: port, reason: "\(error)")
        }

        let request = buildAdminRequest(path: path)

        do {
            try await connection.send(request)
            let responseData = try await connection.receive(maxBytes: Self.maxResponseSize)
            await connection.close()

            let parser = HTTPResponseParser()
            let response = try parser.parse(responseData)
            let body = extractBody(from: responseData)

            return (response, body)
        } catch let error as IcecastError {
            await connection.close()
            throw error
        } catch {
            await connection.close()
            throw IcecastError.connectionLost(reason: "\(error)")
        }
    }

    /// Builds an HTTP GET request for the admin API.
    private func buildAdminRequest(path: String) -> Data {
        var lines: [String] = []
        lines.append("GET \(path) HTTP/1.1")
        lines.append("Host: \(host):\(port)")
        lines.append("Authorization: \(credentials.basicAuthHeaderValue())")
        lines.append("User-Agent: \(HTTPRequestBuilder.userAgent)")
        lines.append("Connection: close")
        lines.append("")
        lines.append("")
        let request = lines.joined(separator: "\r\n")
        return Data(request.utf8)
    }

    /// Extracts the HTTP body from raw response data.
    private func extractBody(from data: Data) -> Data {
        guard let separatorRange = data.findDoubleCRLF() else {
            return Data()
        }
        return data.subdata(in: separatorRange.upperBound..<data.endIndex)
    }

    /// Maps HTTP response status codes to appropriate errors.
    private func handleResponseStatus(_ response: HTTPResponse) throws {
        switch response.statusCode {
        case 200:
            return
        case 401:
            throw IcecastError.authenticationFailed(
                statusCode: 401, message: response.statusMessage
            )
        case 404:
            throw IcecastError.adminAPIUnavailable
        default:
            if response.statusCode >= 500 {
                throw IcecastError.serverError(
                    statusCode: response.statusCode, message: response.statusMessage
                )
            }
            throw IcecastError.unexpectedResponse(
                statusCode: response.statusCode, message: response.statusMessage
            )
        }
    }
}
