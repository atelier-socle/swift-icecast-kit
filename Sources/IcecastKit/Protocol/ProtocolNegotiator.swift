// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Auto-detects and negotiates the appropriate protocol for a server.
///
/// Supports automatic protocol detection (trying PUT then SOURCE),
/// as well as explicit protocol modes for Icecast and SHOUTcast servers.
public actor ProtocolNegotiator {

    private let connectionFactory: @Sendable () -> any TransportConnection
    private let icecastProtocol = IcecastProtocol()
    private let shoutcastProtocol = ShoutcastProtocol()

    /// The fallback connection created during auto-negotiation.
    ///
    /// When auto-negotiation falls back from PUT to SOURCE, the original
    /// connection is closed and a new one is created. This property holds
    /// the new connection. If `nil`, the original connection is still active.
    public private(set) var fallbackConnection: (any TransportConnection)?

    /// Creates a new protocol negotiator.
    ///
    /// - Parameter connectionFactory: A factory closure for creating new transport connections.
    ///   Defaults to ``TransportConnectionFactory/makeConnection()``.
    public init(
        connectionFactory: @Sendable @escaping () -> any TransportConnection = TransportConnectionFactory.makeConnection
    ) {
        self.connectionFactory = connectionFactory
    }

    /// Negotiates the connection protocol.
    ///
    /// Behavior depends on `configuration.protocolMode`:
    /// - `.auto`: Try PUT first. If empty response (pre-2.4.0 server),
    ///   close connection, reconnect, try SOURCE. If SOURCE also fails, throw.
    /// - `.icecastPUT`: Only try PUT, throw on failure.
    /// - `.icecastSOURCE`: Only try SOURCE, throw on failure.
    /// - `.shoutcastV1`: Perform v1 handshake.
    /// - `.shoutcastV2(streamId)`: Perform v2 handshake with stream ID.
    ///
    /// - Parameters:
    ///   - connection: The transport connection to use.
    ///   - configuration: The Icecast configuration.
    ///   - credentials: The authentication credentials.
    /// - Returns: The protocol mode that was successfully negotiated.
    /// - Throws: ``IcecastError`` on negotiation failure.
    public func negotiate(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) async throws -> ProtocolMode {
        fallbackConnection = nil

        switch configuration.protocolMode {
        case .auto:
            return try await negotiateAuto(
                connection: connection,
                configuration: configuration,
                credentials: credentials
            )
        case .icecastPUT:
            try await icecastProtocol.performPUTHandshake(
                connection: connection,
                configuration: configuration,
                credentials: credentials
            )
            return .icecastPUT
        case .icecastSOURCE:
            try await icecastProtocol.performSOURCEHandshake(
                connection: connection,
                configuration: configuration,
                credentials: credentials
            )
            return .icecastSOURCE
        case .shoutcastV1:
            _ = try await shoutcastProtocol.performV1Handshake(
                connection: connection,
                credentials: credentials,
                contentType: configuration.contentType,
                stationInfo: configuration.stationInfo
            )
            return .shoutcastV1
        case .shoutcastV2(let streamId):
            _ = try await shoutcastProtocol.performV2Handshake(
                connection: connection,
                credentials: credentials,
                streamId: streamId,
                contentType: configuration.contentType,
                stationInfo: configuration.stationInfo
            )
            return .shoutcastV2(streamId: streamId)
        }
    }

    // MARK: - Private

    /// Auto-negotiation: try PUT first, fallback to SOURCE.
    private func negotiateAuto(
        connection: any TransportConnection,
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) async throws -> ProtocolMode {
        do {
            try await icecastProtocol.performPUTHandshake(
                connection: connection,
                configuration: configuration,
                credentials: credentials
            )
            return .icecastPUT
        } catch IcecastError.emptyResponse {
            return try await fallbackToSOURCE(
                originalConnection: connection,
                configuration: configuration,
                credentials: credentials
            )
        }
    }

    /// Fallback from PUT to SOURCE with a new connection.
    private func fallbackToSOURCE(
        originalConnection: any TransportConnection,
        configuration: IcecastConfiguration,
        credentials: IcecastCredentials
    ) async throws -> ProtocolMode {
        await originalConnection.close()

        let newConnection = connectionFactory()
        try await newConnection.connect(
            host: configuration.host,
            port: configuration.port,
            useTLS: configuration.useTLS
        )

        do {
            try await icecastProtocol.performSOURCEHandshake(
                connection: newConnection,
                configuration: configuration,
                credentials: credentials
            )
            fallbackConnection = newConnection
            return .icecastSOURCE
        } catch {
            await newConnection.close()
            throw IcecastError.protocolNegotiationFailed(tried: ["PUT", "SOURCE"])
        }
    }
}
