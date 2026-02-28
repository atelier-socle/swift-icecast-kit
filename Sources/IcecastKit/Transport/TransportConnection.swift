// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Protocol abstracting TCP socket communication across platforms.
///
/// Provides a unified interface for network connections regardless of
/// the underlying implementation (Network.framework on Apple, POSIX
/// sockets on Linux).
public protocol TransportConnection: Sendable {

    /// Establishes a TCP connection to the specified host and port.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address to connect to.
    ///   - port: The TCP port number.
    ///   - useTLS: Whether to use TLS encryption.
    /// - Throws: ``IcecastError/connectionFailed(host:port:reason:)`` if the connection fails.
    func connect(host: String, port: Int, useTLS: Bool) async throws

    /// Sends raw data over the connection.
    ///
    /// - Parameter data: The data to send.
    /// - Throws: ``IcecastError/sendFailed(reason:)`` if sending fails.
    func send(_ data: Data) async throws

    /// Receives data from the connection.
    ///
    /// - Parameter maxBytes: The maximum number of bytes to receive.
    /// - Returns: The received data (up to `maxBytes` bytes).
    /// - Throws: ``IcecastError/connectionLost(reason:)`` if the connection is closed.
    func receive(maxBytes: Int) async throws -> Data

    /// Receives data from the connection with a timeout.
    ///
    /// - Parameters:
    ///   - maxBytes: The maximum number of bytes to receive.
    ///   - timeout: The maximum time to wait for data.
    /// - Returns: The received data (up to `maxBytes` bytes).
    /// - Throws: ``IcecastError/connectionTimeout(seconds:)`` if the timeout expires.
    func receive(maxBytes: Int, timeout: TimeInterval) async throws -> Data

    /// Closes the connection gracefully.
    func close() async

    /// Whether the connection is currently established.
    var isConnected: Bool { get async }
}
