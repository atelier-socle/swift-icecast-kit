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

    // MARK: - Advanced Authentication

    /// Performs an Icecast HTTP PUT handshake with advanced authentication.
    ///
    /// Supports Bearer token (direct header), Digest (401 challenge/response),
    /// and Basic auth. For Digest auth, automatically handles the two-step
    /// challenge flow: send initial request → parse 401 challenge → retry
    /// with computed digest response. If the server closes the connection
    /// after 401, a new connection is created via `connectionFactory`.
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - authentication: The authentication method to use.
    ///   - connectionFactory: Factory for creating new connections on Digest retry.
    /// - Returns: A new connection if one was created for Digest retry, `nil` otherwise.
    /// - Throws: ``IcecastError`` on handshake failure.
    @discardableResult
    public func performPUTHandshake(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        authentication: IcecastAuthentication,
        connectionFactory: (@Sendable () -> any TransportConnection)? = nil
    ) async throws -> (any TransportConnection)? {
        let mountpoint = resolveMountpoint(
            configuration.mountpoint,
            authentication: authentication
        )

        let request = buildPUTRequest(
            mountpoint: mountpoint,
            configuration: configuration,
            authentication: authentication
        )

        try await connection.send(request)
        let response = try await readHandshakeResponse(connection: connection)

        // Handle Digest auth 401 challenge/response
        if response.statusCode == 401,
            case .digest(let username, let password) = authentication
        {
            let handler = DigestAuthHandler(
                username: username, password: password
            )
            let ctx = DigestRetryContext(
                method: "PUT", mountpoint: mountpoint,
                configuration: configuration,
                connectionFactory: connectionFactory
            )
            return try await handleDigestChallenge(
                response: response,
                connection: connection,
                handler: handler,
                context: ctx,
                buildRequest: { authValue in
                    self.requestBuilder.buildIcecastPUT(
                        mountpoint: mountpoint,
                        authorizationHeaderValue: authValue,
                        host: configuration.host,
                        port: configuration.port,
                        contentType: configuration.contentType,
                        stationInfo: configuration.stationInfo
                    )
                }
            )
        }

        // Handle Bearer token errors
        if case .bearer = authentication {
            try handleBearerResponse(response, mountpoint: mountpoint)
            return nil
        }

        try handleResponse(response, mountpoint: mountpoint)
        return nil
    }

    /// Performs an Icecast SOURCE handshake with advanced authentication.
    ///
    /// Supports Bearer token (direct header), Digest (401 challenge/response),
    /// and Basic auth. If the server closes the connection after a Digest 401,
    /// a new connection is created via `connectionFactory`.
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - authentication: The authentication method to use.
    ///   - connectionFactory: Factory for creating new connections on Digest retry.
    /// - Returns: A new connection if one was created for Digest retry, `nil` otherwise.
    /// - Throws: ``IcecastError`` on handshake failure.
    @discardableResult
    public func performSOURCEHandshake(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        authentication: IcecastAuthentication,
        connectionFactory: (@Sendable () -> any TransportConnection)? = nil
    ) async throws -> (any TransportConnection)? {
        let mountpoint = resolveMountpoint(
            configuration.mountpoint,
            authentication: authentication
        )

        let request = buildSOURCERequest(
            mountpoint: mountpoint,
            configuration: configuration,
            authentication: authentication
        )

        try await connection.send(request)
        let response = try await readSOURCEResponse(connection: connection)

        // Handle Digest auth 401 challenge/response
        if response.statusCode == 401,
            case .digest(let username, let password) = authentication
        {
            let handler = DigestAuthHandler(
                username: username, password: password
            )
            let ctx = DigestRetryContext(
                method: "SOURCE", mountpoint: mountpoint,
                configuration: configuration,
                connectionFactory: connectionFactory
            )
            return try await handleDigestChallenge(
                response: response,
                connection: connection,
                handler: handler,
                context: ctx,
                buildRequest: { authValue in
                    self.requestBuilder.buildIcecastSOURCE(
                        mountpoint: mountpoint,
                        authorizationHeaderValue: authValue,
                        contentType: configuration.contentType,
                        stationInfo: configuration.stationInfo
                    )
                }
            )
        }

        // Handle Bearer token errors
        if case .bearer = authentication {
            try handleBearerResponse(response, mountpoint: mountpoint)
            return nil
        }

        try handleResponse(response, mountpoint: mountpoint)
        return nil
    }

    // MARK: - Private

    /// Context for Digest challenge/response retry, bundling connection retry parameters.
    private struct DigestRetryContext {
        let method: String
        let mountpoint: String
        let configuration: IcecastConfiguration
        let connectionFactory: (@Sendable () -> any TransportConnection)?
    }

    /// Handles a Digest auth 401 challenge by computing the response and retrying.
    ///
    /// Tries to retry on the existing connection (keep-alive). If the server
    /// closed the connection after 401, falls back to creating a new connection
    /// via `connectionFactory`.
    ///
    /// - Returns: A new connection if one was created, `nil` if the original was reused.
    private func handleDigestChallenge(
        response: HTTPResponse,
        connection: any TransportConnection,
        handler: DigestAuthHandler,
        context: DigestRetryContext,
        buildRequest: (String) -> Data
    ) async throws -> (any TransportConnection)? {
        guard let wwwAuth = response.headers["www-authenticate"] else {
            throw IcecastError.digestAuthFailed(
                reason: "Server returned 401 without WWW-Authenticate header"
            )
        }

        guard let challenge = handler.parseChallenge(wwwAuth) else {
            throw IcecastError.digestAuthFailed(
                reason: "Could not parse Digest challenge"
            )
        }

        let digestHeader = handler.authorizationHeader(
            for: challenge, method: context.method, uri: context.mountpoint
        )
        let retryRequest = buildRequest(digestHeader)

        // Try keep-alive first, fall back to new connection
        let (retryData, newConnection) = try await sendDigestRetry(
            request: retryRequest,
            connection: connection,
            configuration: context.configuration,
            connectionFactory: context.connectionFactory
        )

        let effectiveConnection = newConnection ?? connection

        guard !retryData.isEmpty else {
            if let conn = newConnection { await conn.close() }
            throw IcecastError.digestAuthFailed(
                reason: "Empty response after Digest authentication"
            )
        }

        do {
            var retryResponse = try responseParser.parse(retryData)

            if retryResponse.statusCode == 100 {
                let finalData = try await effectiveConnection.receive(
                    maxBytes: Self.maxResponseSize,
                    timeout: Self.defaultTimeout
                )
                retryResponse = try responseParser.parse(finalData)
            }

            if retryResponse.statusCode == 401 {
                if let conn = newConnection { await conn.close() }
                throw IcecastError.digestAuthFailed(
                    reason: "Server rejected Digest credentials"
                )
            }

            try handleResponse(retryResponse, mountpoint: context.mountpoint)
            return newConnection
        } catch {
            if let conn = newConnection { await conn.close() }
            throw error
        }
    }

    /// Sends the Digest retry request, trying keep-alive first.
    ///
    /// If the existing connection is still open (keep-alive), reuses it.
    /// If the send fails (server closed connection after 401), creates a
    /// new connection via the factory and retries on it.
    ///
    /// - Returns: The response data and the new connection (if one was created).
    private func sendDigestRetry(
        request: Data,
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        connectionFactory: (@Sendable () -> any TransportConnection)?
    ) async throws -> (Data, (any TransportConnection)?) {
        do {
            try await connection.send(request)
            let data = try await connection.receive(
                maxBytes: Self.maxResponseSize,
                timeout: Self.defaultTimeout
            )
            return (data, nil)
        } catch {
            guard let factory = connectionFactory else { throw error }
            let newConn = factory()
            do {
                try await newConn.connect(
                    host: configuration.host,
                    port: configuration.port,
                    useTLS: configuration.useTLS
                )
                try await newConn.send(request)
                let data = try await newConn.receive(
                    maxBytes: Self.maxResponseSize,
                    timeout: Self.defaultTimeout
                )
                return (data, newConn)
            } catch {
                await newConn.close()
                throw error
            }
        }
    }

    /// Handles Bearer token-specific response codes.
    private func handleBearerResponse(
        _ response: HTTPResponse, mountpoint: String
    ) throws {
        switch response.statusCode {
        case 200:
            return
        case 401:
            throw IcecastError.tokenExpired
        case 403:
            throw IcecastError.tokenInvalid
        default:
            try handleResponse(response, mountpoint: mountpoint)
        }
    }

    /// Resolves the effective mountpoint for query token authentication.
    private func resolveMountpoint(
        _ mountpoint: String,
        authentication: IcecastAuthentication
    ) -> String {
        if case .queryToken(let key, let value) = authentication {
            return QueryTokenAuth(key: key, value: value).apply(to: mountpoint)
        }
        return mountpoint
    }

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

// MARK: - Request Building & Response Reading

extension IcecastProtocol {

    /// Builds a PUT request with the given authentication method.
    private func buildPUTRequest(
        mountpoint: String,
        configuration: IcecastConfiguration,
        authentication: IcecastAuthentication
    ) -> Data {
        if let authHeader = authentication.initialAuthorizationHeader() {
            return requestBuilder.buildIcecastPUT(
                mountpoint: mountpoint,
                authorizationHeaderValue: authHeader,
                host: configuration.host,
                port: configuration.port,
                contentType: configuration.contentType,
                stationInfo: configuration.stationInfo
            )
        }

        // Challenge-based auth (Digest): send without Authorization header
        // so the server responds with 401 + WWW-Authenticate challenge.
        return requestBuilder.buildIcecastPUT(
            mountpoint: mountpoint,
            host: configuration.host,
            port: configuration.port,
            contentType: configuration.contentType,
            stationInfo: configuration.stationInfo
        )
    }

    /// Builds a SOURCE request with the given authentication method.
    private func buildSOURCERequest(
        mountpoint: String,
        configuration: IcecastConfiguration,
        authentication: IcecastAuthentication
    ) -> Data {
        if let authHeader = authentication.initialAuthorizationHeader() {
            return requestBuilder.buildIcecastSOURCE(
                mountpoint: mountpoint,
                authorizationHeaderValue: authHeader,
                contentType: configuration.contentType,
                stationInfo: configuration.stationInfo
            )
        }

        // Challenge-based auth (Digest): send without Authorization header.
        return requestBuilder.buildIcecastSOURCE(
            mountpoint: mountpoint,
            contentType: configuration.contentType,
            stationInfo: configuration.stationInfo
        )
    }

    /// Reads a handshake response, handling HTTP 100 Continue.
    private func readHandshakeResponse(
        connection: any TransportConnection
    ) async throws -> HTTPResponse {
        let data = try await connection.receive(
            maxBytes: Self.maxResponseSize,
            timeout: Self.defaultTimeout
        )
        guard !data.isEmpty else {
            throw IcecastError.emptyResponse
        }
        let response = try responseParser.parse(data)
        if response.statusCode == 100 {
            let finalData = try await connection.receive(
                maxBytes: Self.maxResponseSize,
                timeout: Self.defaultTimeout
            )
            return try responseParser.parse(finalData)
        }
        return response
    }

    /// Reads a SOURCE handshake response (no 100 Continue handling).
    private func readSOURCEResponse(
        connection: any TransportConnection
    ) async throws -> HTTPResponse {
        let data = try await connection.receive(
            maxBytes: Self.maxResponseSize,
            timeout: Self.defaultTimeout
        )
        guard !data.isEmpty else {
            throw IcecastError.emptyResponse
        }
        return try responseParser.parse(data)
    }
}
