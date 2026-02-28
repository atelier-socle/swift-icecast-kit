// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Handles Icecast protocol handshakes (PUT and SOURCE methods).
///
/// Implements the connect → authenticate → ready sequences for both
/// modern HTTP PUT (Icecast 2.4+) and legacy SOURCE (pre-2.4.0) methods.
public struct IcecastProtocol: Sendable {

    /// The default timeout for reading server responses, in seconds.
    static let defaultTimeout: TimeInterval = 5.0

    /// The maximum response size to read, in bytes.
    static let maxResponseSize = 4096

    private let requestBuilder = HTTPRequestBuilder()
    private let responseParser = HTTPResponseParser()

    /// Creates a new Icecast protocol handler.
    public init() {}

    /// Performs an Icecast HTTP PUT handshake (modern, since 2.4.0).
    ///
    /// Sequence:
    /// 1. Send PUT request with headers
    /// 2. Read server response
    /// 3. Handle 100 Continue (read again for final status)
    /// 4. Map response to success or specific error
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - credentials: The authentication credentials.
    /// - Throws: ``IcecastError`` on handshake failure.
    public func performPUTHandshake(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) async throws {
        let request = requestBuilder.buildIcecastPUT(
            mountpoint: configuration.mountpoint,
            credentials: credentials,
            host: configuration.host,
            port: configuration.port,
            contentType: configuration.contentType,
            stationInfo: configuration.stationInfo
        )

        try await connection.send(request)

        let responseData = try await connection.receive(
            maxBytes: Self.maxResponseSize,
            timeout: Self.defaultTimeout
        )

        guard !responseData.isEmpty else {
            throw IcecastError.emptyResponse
        }

        let response = try responseParser.parse(responseData)

        if response.statusCode == 100 {
            let finalData = try await connection.receive(
                maxBytes: Self.maxResponseSize,
                timeout: Self.defaultTimeout
            )
            let finalResponse = try responseParser.parse(finalData)
            try handleResponse(finalResponse, mountpoint: configuration.mountpoint)
            return
        }

        try handleResponse(response, mountpoint: configuration.mountpoint)
    }

    /// Performs an Icecast SOURCE handshake (legacy, pre-2.4.0).
    ///
    /// Sequence:
    /// 1. Send SOURCE request with headers
    /// 2. Read server response
    /// 3. Map response to success or specific error
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - credentials: The authentication credentials.
    /// - Throws: ``IcecastError`` on handshake failure.
    public func performSOURCEHandshake(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) async throws {
        let request = requestBuilder.buildIcecastSOURCE(
            mountpoint: configuration.mountpoint,
            credentials: credentials,
            contentType: configuration.contentType,
            stationInfo: configuration.stationInfo
        )

        try await connection.send(request)

        let responseData = try await connection.receive(
            maxBytes: Self.maxResponseSize,
            timeout: Self.defaultTimeout
        )

        guard !responseData.isEmpty else {
            throw IcecastError.emptyResponse
        }

        let response = try responseParser.parse(responseData)
        try handleResponse(response, mountpoint: configuration.mountpoint)
    }

    // MARK: - Private

    /// Maps an HTTP response to success or a specific error.
    private func handleResponse(_ response: HTTPResponse, mountpoint: String) throws {
        switch response.statusCode {
        case 200:
            return
        case 401:
            throw IcecastError.authenticationFailed(
                statusCode: 401,
                message: response.statusMessage
            )
        case 403:
            throw map403Error(response, mountpoint: mountpoint)
        case 500...599:
            throw IcecastError.serverError(
                statusCode: response.statusCode,
                message: response.statusMessage
            )
        default:
            throw IcecastError.unexpectedResponse(
                statusCode: response.statusCode,
                message: response.statusMessage
            )
        }
    }

    /// Maps a 403 response to a specific error based on the status message.
    private func map403Error(_ response: HTTPResponse, mountpoint: String) -> IcecastError {
        let message = response.statusMessage.lowercased()
        if message.contains("mountpoint in use") {
            return .mountpointInUse(mountpoint)
        } else if message.contains("content-type not supported") || message.contains("no content-type given") {
            return .contentTypeNotSupported(response.statusMessage)
        } else if message.contains("too many sources") {
            return .tooManySources
        }
        return .unexpectedResponse(statusCode: 403, message: response.statusMessage)
    }
}
