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
    /// with computed digest response.
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - authentication: The authentication method to use.
    /// - Throws: ``IcecastError`` on handshake failure.
    public func performPUTHandshake(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        authentication: IcecastAuthentication
    ) async throws {
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
            try await handleDigestChallenge(
                response: response,
                connection: connection,
                method: "PUT",
                mountpoint: mountpoint,
                handler: handler,
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
            return
        }

        // Handle Bearer token errors
        if case .bearer = authentication {
            try handleBearerResponse(response, mountpoint: mountpoint)
            return
        }

        try handleResponse(response, mountpoint: mountpoint)
    }

    /// Performs an Icecast SOURCE handshake with advanced authentication.
    ///
    /// Supports Bearer token (direct header), Digest (401 challenge/response),
    /// and Basic auth.
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - authentication: The authentication method to use.
    /// - Throws: ``IcecastError`` on handshake failure.
    public func performSOURCEHandshake(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        authentication: IcecastAuthentication
    ) async throws {
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
            try await handleDigestChallenge(
                response: response,
                connection: connection,
                method: "SOURCE",
                mountpoint: mountpoint,
                handler: handler,
                buildRequest: { authValue in
                    self.requestBuilder.buildIcecastSOURCE(
                        mountpoint: mountpoint,
                        authorizationHeaderValue: authValue,
                        contentType: configuration.contentType,
                        stationInfo: configuration.stationInfo
                    )
                }
            )
            return
        }

        // Handle Bearer token errors
        if case .bearer = authentication {
            try handleBearerResponse(response, mountpoint: mountpoint)
            return
        }

        try handleResponse(response, mountpoint: mountpoint)
    }

    // MARK: - Private

    /// Handles a Digest auth 401 challenge by computing the response and retrying.
    private func handleDigestChallenge(
        response: HTTPResponse,
        connection: any TransportConnection,
        method: String,
        mountpoint: String,
        handler: DigestAuthHandler,
        buildRequest: (String) -> Data
    ) async throws {
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
            for: challenge, method: method, uri: mountpoint
        )
        let retryRequest = buildRequest(digestHeader)

        try await connection.send(retryRequest)
        let retryData = try await connection.receive(
            maxBytes: Self.maxResponseSize,
            timeout: Self.defaultTimeout
        )

        guard !retryData.isEmpty else {
            throw IcecastError.digestAuthFailed(
                reason: "Empty response after Digest authentication"
            )
        }

        var retryResponse = try responseParser.parse(retryData)

        if retryResponse.statusCode == 100 {
            let finalData = try await connection.receive(
                maxBytes: Self.maxResponseSize,
                timeout: Self.defaultTimeout
            )
            retryResponse = try responseParser.parse(finalData)
        }

        if retryResponse.statusCode == 401 {
            throw IcecastError.digestAuthFailed(
                reason: "Server rejected Digest credentials"
            )
        }

        try handleResponse(retryResponse, mountpoint: mountpoint)
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

        let creds = authentication.credentials ?? IcecastCredentials(password: "")
        return requestBuilder.buildIcecastPUT(
            mountpoint: mountpoint,
            credentials: creds,
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

        let creds = authentication.credentials ?? IcecastCredentials(password: "")
        return requestBuilder.buildIcecastSOURCE(
            mountpoint: mountpoint,
            credentials: creds,
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
