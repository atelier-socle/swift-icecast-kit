// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Handles SHOUTcast v1/v2 protocol handshakes.
///
/// Implements the authentication and stream header sequences for
/// SHOUTcast v1 (password-only) and v2 (with stream ID).
public struct ShoutcastProtocol: Sendable {

    /// The default timeout for reading server responses, in seconds.
    static let defaultTimeout: TimeInterval = 5.0

    /// The maximum response size to read, in bytes.
    static let maxResponseSize = 4096

    private let requestBuilder = HTTPRequestBuilder()
    private let responseParser = HTTPResponseParser()

    /// Creates a new SHOUTcast protocol handler.
    public init() {}

    /// Performs a SHOUTcast v1 handshake.
    ///
    /// Sequence:
    /// 1. Send password line (`password\r\n`)
    /// 2. Read response — expect `OK2` + optional `icy-caps:N`
    /// 3. If OK2 → send stream headers (content-type, icy-name, etc.)
    /// 4. Ready to stream after headers sent
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - credentials: The authentication credentials.
    ///   - contentType: The audio content type.
    ///   - stationInfo: Station metadata for icy-* headers.
    /// - Returns: The parsed SHOUTcast authentication response.
    /// - Throws: ``IcecastError`` on handshake failure.
    public func performV1Handshake(
        connection: any TransportConnection,
        credentials: IcecastCredentials,
        contentType: AudioContentType,
        stationInfo: StationInfo
    ) async throws -> ShoutcastAuthResponse {
        let authData = requestBuilder.buildShoutcastV1Auth(password: credentials.password)
        try await connection.send(authData)

        let responseData = try await connection.receive(
            maxBytes: Self.maxResponseSize,
            timeout: Self.defaultTimeout
        )

        let authResponse = try responseParser.parseShoutcastAuth(responseData)

        guard authResponse.isOK else {
            throw IcecastError.authenticationFailed(
                statusCode: 0,
                message: "SHOUTcast server rejected credentials"
            )
        }

        let headers = requestBuilder.buildShoutcastHeaders(
            contentType: contentType,
            stationInfo: stationInfo
        )
        try await connection.send(headers)

        return authResponse
    }

    /// Performs a SHOUTcast v2 handshake (v1-compat mode with stream ID).
    ///
    /// Sequence:
    /// 1. Format password as `password:#streamId`
    /// 2. Same handshake as v1
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - credentials: The authentication credentials.
    ///   - streamId: The stream identifier.
    ///   - contentType: The audio content type.
    ///   - stationInfo: Station metadata for icy-* headers.
    /// - Returns: The parsed SHOUTcast authentication response.
    /// - Throws: ``IcecastError`` on handshake failure.
    public func performV2Handshake(
        connection: any TransportConnection,
        credentials: IcecastCredentials,
        streamId: Int,
        contentType: AudioContentType,
        stationInfo: StationInfo
    ) async throws -> ShoutcastAuthResponse {
        let v2Password = "\(credentials.password):#\(streamId)"
        let v2Credentials = IcecastCredentials(
            username: credentials.username,
            password: v2Password
        )
        return try await performV1Handshake(
            connection: connection,
            credentials: v2Credentials,
            contentType: contentType,
            stationInfo: stationInfo
        )
    }

    /// Calculates the source port for SHOUTcast (listener port + 1).
    ///
    /// SHOUTcast v1/v2 uses a separate port for source connections,
    /// which is the listener port plus one.
    ///
    /// - Parameter port: The listener port number.
    /// - Returns: The source port number.
    public func sourcePort(forListenerPort port: Int) -> Int {
        port + 1
    }
}
