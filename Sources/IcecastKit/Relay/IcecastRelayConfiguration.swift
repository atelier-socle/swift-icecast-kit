// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Configuration for an ``IcecastRelay`` listener connection.
///
/// Specifies the source stream URL and connection parameters for
/// receiving audio from a remote Icecast or SHOUTcast server.
public struct IcecastRelayConfiguration: Sendable {

    /// Full URL of the source stream (e.g. `"https://radio.example.com:8000/live.mp3"`).
    public var sourceURL: String

    /// Credentials if the stream requires authentication. `nil` for public streams.
    public var credentials: IcecastCredentials?

    /// Whether to request ICY metadata from the server (`Icy-MetaData: 1` header).
    /// Default: `true`.
    public var requestICYMetadata: Bool

    /// Receive buffer size in bytes. Default: `65536`.
    public var bufferSize: Int

    /// User-Agent header sent to the server.
    public var userAgent: String

    /// Auto-reconnect policy if the source stream ends or drops.
    /// `nil` = no reconnect (stop on disconnect).
    public var reconnectPolicy: ReconnectPolicy?

    /// Connection timeout in seconds. Default: `10.0`.
    public var connectionTimeout: TimeInterval

    /// Creates a relay configuration.
    ///
    /// - Parameters:
    ///   - sourceURL: Full URL of the source stream.
    ///   - credentials: Authentication credentials, or `nil` for public streams.
    ///   - requestICYMetadata: Whether to request ICY metadata. Default: `true`.
    ///   - bufferSize: Receive buffer size in bytes. Default: `65536`.
    ///   - userAgent: User-Agent header. Default: `"IcecastKit/0.2.0"`.
    ///   - reconnectPolicy: Auto-reconnect policy. Default: `nil`.
    ///   - connectionTimeout: Connection timeout in seconds. Default: `10.0`.
    public init(
        sourceURL: String,
        credentials: IcecastCredentials? = nil,
        requestICYMetadata: Bool = true,
        bufferSize: Int = 65536,
        userAgent: String = "IcecastKit/0.2.0",
        reconnectPolicy: ReconnectPolicy? = nil,
        connectionTimeout: TimeInterval = 10.0
    ) {
        self.sourceURL = sourceURL
        self.credentials = credentials
        self.requestICYMetadata = requestICYMetadata
        self.bufferSize = bufferSize
        self.userAgent = userAgent
        self.reconnectPolicy = reconnectPolicy
        self.connectionTimeout = connectionTimeout
    }
}
